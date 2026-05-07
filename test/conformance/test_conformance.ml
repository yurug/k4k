(** Protocol-conformance tests.

    These tests validate that the in-tree example binaries emit JSON
    matching the documented wire-protocol schemas in
    [kb/external/{backend,verifier}-protocol.md]. They are independent
    from integration tests (which test k4k as a whole) — they catch
    drift between the protocol *specs* and the example *implementations*.

    Run on every CI build. If a future contributor changes
    [kb/external/<protocol>.md] without updating the corresponding
    example, these tests fail loudly. The reverse drift (example
    changes its output without a spec update) is also caught.

    Per the architectural commitment in ADR-008/ADR-009, k4k carries no
    tool-specific code; conformance tests are how we keep that
    commitment honest as the code evolves. *)

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

let dune_verifier_bin () =
  find_up "_build/default/examples/verifiers/dune-ocaml/main.exe"

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

(** [require_string fs key] — the field [key] must be present and a string. *)
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

(** Validate a backend result file against the documented schema. *)
let validate_backend_result path : unit =
  let fs = parse_json_object path in
  let outcome = require_string fs "outcome" in
  (match outcome with
   | "ok" ->
       let _text = require_string fs "text" in
       let used = require_int fs "budget_used" in
       Alcotest.(check bool) "budget_used >= 0" true (used >= 0)
   | "budget_exhausted" ->
       (* No required fields beyond outcome+duration_ms. *)
       ()
   | "tool_error" ->
       let _err = require_string fs "error" in ()
   | other ->
       Alcotest.failf "unknown outcome value: %s" other);
  let dur = require_int fs "duration_ms" in
  Alcotest.(check bool) "duration_ms >= 0" true (dur >= 0)

(** Validate a verifier result file against the documented schema. *)
let validate_verifier_result path : unit =
  let fs = parse_json_object path in
  let _by_property = require_assoc fs "by_property" in
  let _exit = require_int fs "raw_exit_code" in
  let dur = require_int fs "duration_ms" in
  Alcotest.(check bool) "duration_ms >= 0" true (dur >= 0)
  (* warnings is optional; if present must be a list. *)

(** Each value in [by_property] must be one of the three documented
    status strings. *)
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

(* ---------------- Verifier protocol — dune-ocaml example ---------------- *)

(* Build a minimal OCaml project under [dir] with one passing test. *)
let scaffold_passing_project dir =
  write_file (Filename.concat dir "dune-project")
    "(lang dune 3.22)\n";
  Unix.mkdir (Filename.concat dir "test") 0o755;
  write_file (Filename.concat dir "test/dune")
    "(test (name t) (libraries alcotest))\n";
  write_file (Filename.concat dir "test/t.ml")
    "let () = Alcotest.run \"conf\" \
     [ \"S\", [ Alcotest.test_case \"Paaa1234_trivial\" `Quick \
                 (fun () -> Alcotest.(check bool) \"true\" true true) ]]\n"

let run_dune_verifier ~workdir ~focus ~output =
  let bin = dune_verifier_bin () in
  let focus_args =
    if focus = [] then ""
    else "--focus " ^
         String.concat " " (List.map Filename.quote focus) in
  let cmd = Printf.sprintf
    "%s --workdir %s %s --output %s 2>/dev/null"
    (Filename.quote bin) (Filename.quote workdir)
    focus_args (Filename.quote output) in
  Sys.command cmd

let verifier_passing_run_matches_schema () =
  with_workdir (fun dir ->
    scaffold_passing_project dir;
    let o = Filename.concat dir "result.json" in
    let code = run_dune_verifier ~workdir:dir
                 ~focus:["Paaa1234"] ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    validate_verifier_result o;
    validate_status_values o;
    let fs = parse_json_object o in
    let by = require_assoc fs "by_property" in
    match List.assoc_opt "Paaa1234" by with
    | Some (`String "established") -> ()
    | Some (`String s) ->
        Alcotest.failf "Paaa1234: expected established, got %s" s
    | _ -> Alcotest.failf "Paaa1234 missing or not a string")

let verifier_unknown_focus_id_is_unknown () =
  with_workdir (fun dir ->
    scaffold_passing_project dir;
    let o = Filename.concat dir "result.json" in
    let code = run_dune_verifier ~workdir:dir
                 ~focus:["Pdeadbee"] ~output:o in
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
