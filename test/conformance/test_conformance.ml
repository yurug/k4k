(** Protocol-conformance tests.

    These tests validate that the in-tree example backend binaries
    emit JSON matching the documented wire-protocol schemas in
    [kb/external/{backend,verifier}-protocol.md]. They are independent
    from integration tests (which test k4k as a whole) — they catch
    drift between the protocol *specs* and the example *implementations*.

    Per ADR-011 / round-5 I2: v2 ships no Tier-C verifier example. The
    verifier-side conformance is exercised against a synthetic stub at
    [test/conformance/fixtures/synthetic-verifier.sh] that conforms to
    the wire protocol without invoking any toolchain. *)

(* ---------------- Locate the example binaries ---------------- *)

let find_up rel =
  let here = Sys.getcwd () in
  let rec loop dir =
    let cand = Filename.concat dir rel in
    if Sys.file_exists cand then cand
    else
      let p = Filename.dirname dir in
      if p = dir then failwith ("not found: " ^ rel)
      else loop p
  in loop here

let ollama_bin () =
  find_up "_build/default/examples/backends/ollama/main.exe"

let synthetic_verifier_bin () =
  (* Resolve via the source tree (not _build/) since dune (deps ...)
     makes the file available next to the test executable but doesn't
     install it under _build/default/.
     We walk up to the dune-project root and append the fixtures path. *)
  let rec find_root dir =
    if Sys.file_exists (Filename.concat dir "dune-project") then dir
    else
      let p = Filename.dirname dir in
      if p = dir then failwith "dune-project root not found"
      else find_root p
  in
  let root = find_root (Sys.getcwd ()) in
  Filename.concat root "test/conformance/fixtures/synthetic-verifier.sh"

(* ---------------- Tempdir helper ---------------- *)

let with_workdir f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "k4k-conf-%d-%d"
       (Unix.getpid ()) (Random.int 1_000_000)) in
  Unix.mkdir dir 0o755;
  let cleanup () =
    let _ = Sys.command (Printf.sprintf "rm -rf %s"
                           (Filename.quote dir)) in ()
  in
  match f dir with
  | r -> cleanup (); r
  | exception e -> cleanup (); raise e

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let read_file path =
  let ic = open_in path in
  let buf = Buffer.create 256 in
  (try while true do Buffer.add_channel buf ic 4096 done; assert false
   with End_of_file -> close_in ic);
  Buffer.contents buf

(* ---------------- Schema validators ---------------- *)

let require_string fs key =
  match List.assoc_opt key fs with
  | Some (`String s) -> s
  | Some _ -> Alcotest.failf "%s: not a string" key
  | None -> Alcotest.failf "%s: missing" key

let require_int fs key =
  match List.assoc_opt key fs with
  | Some (`Int i) -> i
  | Some _ -> Alcotest.failf "%s: not an int" key
  | None -> Alcotest.failf "%s: missing" key

let require_assoc fs key =
  match List.assoc_opt key fs with
  | Some (`Assoc a) -> a
  | Some _ -> Alcotest.failf "%s: not an object" key
  | None -> Alcotest.failf "%s: missing" key

let parse_json_object path =
  let raw = read_file path in
  match Yojson.Safe.from_string raw with
  | `Assoc fs -> fs
  | exception Yojson.Json_error msg ->
      Alcotest.failf "result file is not valid JSON: %s" msg
  | _ -> Alcotest.failf "result file is not a JSON object"

let validate_backend_result path : unit =
  let fs = parse_json_object path in
  let outcome = require_string fs "outcome" in
  (match outcome with
   | "ok" ->
       let _text = require_string fs "text" in
       let used = require_int fs "budget_used" in
       Alcotest.(check bool) "budget_used >= 0" true (used >= 0)
   | "budget_exhausted" -> ()
   | "tool_error" ->
       let _err = require_string fs "error" in ()
   | other ->
       Alcotest.failf "unknown outcome value: %s" other);
  let dur = require_int fs "duration_ms" in
  Alcotest.(check bool) "duration_ms >= 0" true (dur >= 0)

let validate_verifier_result path : unit =
  let fs = parse_json_object path in
  let _by_property = require_assoc fs "by_property" in
  let _exit = require_int fs "raw_exit_code" in
  let dur = require_int fs "duration_ms" in
  Alcotest.(check bool) "duration_ms >= 0" true (dur >= 0)

let validate_status_values path =
  let fs = parse_json_object path in
  let by = require_assoc fs "by_property" in
  List.iter (fun (k, v) ->
    match v with
    | `String ("established" | "contradicted" | "unknown") -> ()
    | `String other ->
        Alcotest.failf "invalid status for %s: %s" k other
    | _ ->
        Alcotest.failf "%s: not a string" k) by

(* ---------------- Backend protocol — Ollama example ---------------- *)

let run_ollama ~mock ~purpose ~budget ~prompt ~output =
  let bin = ollama_bin () in
  let cmd = Printf.sprintf
    "%s --mock-response %s --purpose %s --prompt-file %s \
     --budget %d --output %s 2>/dev/null"
    (Filename.quote bin) (Filename.quote mock)
    purpose (Filename.quote prompt) budget (Filename.quote output) in
  Sys.command cmd

let backend_ok_outcome_matches_schema () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m
      {|{"response":"hello","prompt_eval_count":3,"eval_count":2}|};
    let o = Filename.concat dir "result.json" in
    let code = run_ollama ~mock:m ~purpose:"formalization"
                 ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    validate_backend_result o)

let backend_budget_exhausted_outcome_matches_schema () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m
      {|{"response":"x","prompt_eval_count":80,"eval_count":50}|};
    let o = Filename.concat dir "result.json" in
    let code = run_ollama ~mock:m ~purpose:"gap-step"
                 ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    validate_backend_result o;
    let fs = parse_json_object o in
    Alcotest.(check string) "outcome" "budget_exhausted"
      (require_string fs "outcome"))

let backend_tool_error_outcome_matches_schema () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m {|{"error":"model 'bogus' not found"}|};
    let o = Filename.concat dir "result.json" in
    let code = run_ollama ~mock:m ~purpose:"kb-regen"
                 ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    validate_backend_result o;
    let fs = parse_json_object o in
    Alcotest.(check string) "outcome" "tool_error"
      (require_string fs "outcome"))

let backend_accepts_all_three_purposes () =
  List.iter (fun purpose ->
    with_workdir (fun dir ->
      let p = Filename.concat dir "prompt.txt" in
      write_file p "x";
      let m = Filename.concat dir "mock.json" in
      write_file m
        {|{"response":"r","prompt_eval_count":1,"eval_count":1}|};
      let o = Filename.concat dir "result.json" in
      let code = run_ollama ~mock:m ~purpose ~budget:100
                   ~prompt:p ~output:o in
      Alcotest.(check int)
        (Printf.sprintf "purpose=%s exit 0" purpose) 0 code;
      validate_backend_result o))
  ["formalization"; "gap-step"; "kb-regen"]

(* ---------------- Verifier protocol — synthetic stub ---------------- *)

let run_synthetic_verifier ~workdir ~focus ~output ~established =
  let bin = synthetic_verifier_bin () in
  let focus_args =
    if focus = [] then ""
    else "--focus " ^
         String.concat " " (List.map Filename.quote focus) in
  let cmd = Printf.sprintf
    "K4K_SYNTH_ESTABLISHED=%s %s --workdir %s %s --output %s 2>/dev/null"
    (Filename.quote (String.concat " " established))
    (Filename.quote bin) (Filename.quote workdir)
    focus_args (Filename.quote output) in
  Sys.command cmd

let verifier_passing_run_matches_schema () =
  with_workdir (fun dir ->
    let o = Filename.concat dir "result.json" in
    let code = run_synthetic_verifier ~workdir:dir
                 ~focus:["P1234567"] ~output:o
                 ~established:["P1234567"] in
    Alcotest.(check int) "exit 0" 0 code;
    validate_verifier_result o;
    validate_status_values o;
    let fs = parse_json_object o in
    let by = require_assoc fs "by_property" in
    match List.assoc_opt "P1234567" by with
    | Some (`String "established") -> ()
    | Some (`String s) ->
        Alcotest.failf "P1234567: expected established, got %s" s
    | _ -> Alcotest.failf "P1234567 missing or not a string")

let verifier_unknown_focus_id_is_unknown () =
  with_workdir (fun dir ->
    let o = Filename.concat dir "result.json" in
    let code = run_synthetic_verifier ~workdir:dir
                 ~focus:["Pdeadbee"] ~output:o
                 ~established:[] in
    Alcotest.(check int) "exit 0" 0 code;
    validate_verifier_result o;
    validate_status_values o;
    let fs = parse_json_object o in
    let by = require_assoc fs "by_property" in
    Alcotest.(check string) "unknown id is 'unknown'" "unknown"
      (match List.assoc_opt "Pdeadbee" by with
       | Some (`String s) -> s | _ -> "missing"))

(* ---------------- Suite ---------------- *)

let () =
  Alcotest.run "k4k conformance"
    [ "backend_protocol", [
        Alcotest.test_case "ok_outcome_matches_schema" `Quick
          backend_ok_outcome_matches_schema;
        Alcotest.test_case "budget_exhausted_outcome_matches_schema"
          `Quick backend_budget_exhausted_outcome_matches_schema;
        Alcotest.test_case "tool_error_outcome_matches_schema" `Quick
          backend_tool_error_outcome_matches_schema;
        Alcotest.test_case "accepts_all_three_purposes" `Quick
          backend_accepts_all_three_purposes;
      ];
      "verifier_protocol", [
        Alcotest.test_case "passing_run_matches_schema" `Quick
          verifier_passing_run_matches_schema;
        Alcotest.test_case "unknown_focus_id_is_unknown" `Quick
          verifier_unknown_focus_id_is_unknown;
      ];
    ]
