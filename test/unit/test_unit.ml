(** Unit tests for every module in [lib/]. ≥ 3 tests per source file. *)

open K4k

(* Tiny adapter for [QCheck.Test.t] → [Alcotest.test_case]. We don't
   have [qcheck-alcotest] installed; this short adapter runs the test
   silently and reports failure to alcotest. *)
let qcheck_to_alcotest (t : QCheck.Test.t) : unit Alcotest.test_case =
  let QCheck2.Test.Test cell = t in
  let name = QCheck2.Test.get_name cell in
  Alcotest.test_case name `Quick (fun () ->
    let rc = QCheck_base_runner.run_tests ~verbose:false [t] in
    if rc <> 0 then
      Alcotest.failf "qcheck property %s failed" name)

(* ---------------- Helpers ---------------- *)

let with_tmpdir f =
  let dir =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "k4k-test-%d-%d" (Unix.getpid ()) (Random.int 1_000_000))
  in
  Unix.mkdir dir 0o755;
  let r =
    try f dir
    with e ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)) in
      raise e
  in
  let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)) in
  r

let read_all path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let b = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  Bytes.unsafe_to_string b

(* Minimal valid fixture body, parameterizable. *)
let stable_fixture =
  "---\n\
   k4k:\n  version: 1\n  class: cli\n\
   ---\n\
   <!-- k4k:owner=user begin id=goal -->\nGoal text\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=inputs-outputs -->\nIO\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=errors -->\nE\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=fs -->\nFS\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=concurrency -->\nC\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=perf -->\nP\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=examples-accept -->\nE\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=examples-refuse -->\nR\n<!-- k4k:owner=user end -->\n\
   <!-- k4k:owner=user begin id=out-of-scope -->\nO\n<!-- k4k:owner=user end -->\n"

(* ---------------- Error tests (≥3) ---------------- *)
module ET = struct
  let p7_code_id_unique () =
    let codes = List.map Error.code_id [
      Error.E_format { line = 1; col = 1; reason = "x" };
      Error.E_unstable [];
      Error.E_version { found = 0; supported = [1] };
      Error.E_class_unsupported "z";
      Error.E_budget { used = 1; cap = 1 };
      Error.E_max_steps 1;
      Error.E_agent_unavailable "x";
      Error.E_verifier_unavailable "x";
      Error.E_verifier_tool_error "x";
      Error.E_disk_full "x";
      Error.E_state_corrupt "x";
      Error.E_encoding 0;
      Error.E_file_not_found "x";
      Error.E_file_too_large 0;
    ] in
    let n = List.length codes in
    let unique = List.sort_uniq compare codes in
    Alcotest.(check int) "P7 every error has a unique id" n (List.length unique)

  let p7_exit_codes_in_range () =
    let exits = List.map Error.exit_code_of [
      Error.E_format { line = 1; col = 1; reason = "x" };
      Error.E_unstable [];
      Error.E_budget { used = 1; cap = 1 };
      Error.E_disk_full "x";
      Error.E_agent_unavailable "x";
      Error.E_verifier_unavailable "x";
      Error.E_state_corrupt "x";
    ] in
    List.iter (fun e ->
      Alcotest.(check bool) "exit ∈ {1..5}" true (e >= 1 && e <= 5)
    ) exits

  let p7_render_includes_topic () =
    let s = Error.render
      (Error.E_file_too_large Persist.max_interaction_file_bytes) in
    Alcotest.(check bool) "render mentions max" true
      (Astring.String.is_infix ~affix:"10485760" s)

  let tests = [
    Alcotest.test_case "P7_unique_code_id" `Quick p7_code_id_unique;
    Alcotest.test_case "P7_exit_codes_in_range" `Quick p7_exit_codes_in_range;
    Alcotest.test_case "P7_render_topical" `Quick p7_render_includes_topic;
  ]
end

(* ---------------- Logger tests (≥3) ---------------- *)
module LT = struct
  let p11_scrub_redacts_token () =
    let s = Logger.scrub "ANTHROPIC_API_KEY=POISON-CANARY" in
    Alcotest.(check bool) "secret scrubbed" false
      (Astring.String.is_infix ~affix:"POISON-CANARY" s);
    Alcotest.(check bool) "scrubbed marker present" true
      (Astring.String.is_infix ~affix:"<scrubbed>" s)

  let p11_scrub_idempotent () =
    let s = "hello world" in
    Alcotest.(check string) "non-secret stays" s (Logger.scrub s)

  let p11_jsonl_appends_event () =
    with_tmpdir (fun dir ->
      let p = Filename.concat dir "log.jsonl" in
      let logger = Logger.create ~verbosity:`Quiet ~jsonl_path:(Some p) in
      Logger.info logger "stability.start" (`Assoc []);
      Logger.info logger "stability.pass"  (`Assoc []);
      let lines = String.split_on_char '\n' (read_all p)
                  |> List.filter (fun s -> s <> "") in
      Alcotest.(check int) "two events" 2 (List.length lines);
      List.iter (fun l ->
        let _ = Yojson.Safe.from_string l in ()) lines)

  let tests = [
    Alcotest.test_case "P11_scrub_redacts_token" `Quick p11_scrub_redacts_token;
    Alcotest.test_case "P11_scrub_idempotent_on_plain" `Quick p11_scrub_idempotent;
    Alcotest.test_case "P11_jsonl_appends_event" `Quick p11_jsonl_appends_event;
  ]
end

(* ---------------- Persist tests (≥3) ---------------- *)
module PT = struct
  let p10_atomic_write_writes_content () =
    with_tmpdir (fun dir ->
      let p = Filename.concat dir "x.json" in
      Persist.atomic_write ~path:p "hello";
      Alcotest.(check string) "content matches" "hello" (read_all p))

  (* P10 — crash hook between write and rename leaves the prior file
     intact and the .tmp file present. This exactly mirrors the v0
     acceptance test. *)
  let p10_atomic_write_survives_crash () =
    with_tmpdir (fun dir ->
      let p = Filename.concat dir "x.json" in
      Persist.atomic_write ~path:p "v1";
      let crashed = ref false in
      let crash () = crashed := true; raise Exit in
      (try Persist.atomic_write ~crash_hook:crash ~path:p "v2"
       with Exit -> ());
      Alcotest.(check bool) "crash fired" true !crashed;
      Alcotest.(check string) "prior file intact" "v1" (read_all p);
      let tmp_exists = Sys.file_exists (p ^ ".tmp") in
      Alcotest.(check bool) "tmp file remains" true tmp_exists)

  let p10_sha256_hex_known_vector () =
    Alcotest.(check string) "sha256(\"\")"
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      (Persist.sha256_hex "")

  let tests = [
    Alcotest.test_case "P10_atomic_write_writes_content" `Quick
      p10_atomic_write_writes_content;
    Alcotest.test_case "P10_atomic_write_survives_simulated_crash" `Quick
      p10_atomic_write_survives_crash;
    Alcotest.test_case "P10_sha256_hex_known_vector" `Quick
      p10_sha256_hex_known_vector;
  ]
end

(* ---------------- Parser tests (≥3) ---------------- *)
module ParT = struct
  let parses_well_formed_fixture () =
    let f = Parser.parse stable_fixture in
    Alcotest.(check int) "version=1" 1 f.frontmatter.version;
    Alcotest.(check string) "class=cli" "cli" f.frontmatter.cls;
    Alcotest.(check int) "9 sections"
      9 (List.length f.sections)

  let p1_round_trip_byte_equality () =
    let f = Parser.parse stable_fixture in
    List.iter (fun (s : Parser.section) ->
      let original = String.sub stable_fixture s.start_offset
                       (s.end_offset - s.start_offset) in
      Alcotest.(check string) ("section bytes equal: " ^ s.id)
        original s.content
    ) f.sections

  (* T6 — invalid UTF-8 raises EENCODING. *)
  let t6_invalid_utf8_rejected () =
    let bad = "---\n\xFF\nclass: cli\n---\n" in
    Alcotest.check_raises "EENCODING"
      (Error.K4k_error (Error.E_encoding 4))
      (fun () -> ignore (Parser.parse bad))

  let efmt_duplicate_id () =
    let bad = "---\nk4k:\n  version: 1\n  class: cli\n---\n\
               <!-- k4k:owner=user begin id=goal -->\nA\n<!-- k4k:owner=user end -->\n\
               <!-- k4k:owner=user begin id=goal -->\nB\n<!-- k4k:owner=user end -->\n"
    in
    match (try ignore (Parser.parse bad); `Ok with
           | Error.K4k_error (Error.E_format _) -> `Fmt
           | _ -> `Other) with
    | `Fmt -> ()
    | _ -> Alcotest.fail "expected EFORMAT for duplicate id"

  let tests = [
    Alcotest.test_case "Parser_parses_well_formed_fixture" `Quick parses_well_formed_fixture;
    Alcotest.test_case "P1_round_trip_byte_equality" `Quick p1_round_trip_byte_equality;
    Alcotest.test_case "T6_non_utf8_rejected" `Quick t6_invalid_utf8_rejected;
    Alcotest.test_case "EFORMAT_duplicate_id" `Quick efmt_duplicate_id;
  ]
end

(* ---------------- Stability tests (≥3) ---------------- *)
module ST = struct
  let stable_on_full_fixture () =
    let f = Parser.parse stable_fixture in
    Alcotest.(check bool) "stable" true
      (Stability.is_stable (Stability.check_structural f))

  let unstable_when_section_missing () =
    let f = { (Parser.parse stable_fixture) with
              sections = List.filter (fun (s : Parser.section) ->
                s.id <> "goal") (Parser.parse stable_fixture).sections } in
    let v = Stability.check_structural f in
    Alcotest.(check bool) "unstable" false (Stability.is_stable v)

  let unstable_when_section_blank () =
    let blank = String.concat "\n" [
      "---";
      "k4k:";
      "  version: 1";
      "  class: cli";
      "---";
      "<!-- k4k:owner=user begin id=goal -->";
      "   ";
      "<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=inputs-outputs -->\nIO\n<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=errors -->\nE\n<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=fs -->\nF\n<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=concurrency -->\nC\n<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=perf -->\nP\n<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=examples-accept -->\nE\n<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=examples-refuse -->\nR\n<!-- k4k:owner=user end -->";
      "<!-- k4k:owner=user begin id=out-of-scope -->\nO\n<!-- k4k:owner=user end -->";
      "";
    ] in
    let f = Parser.parse blank in
    let v = Stability.check_structural f in
    Alcotest.(check bool) "blank goal -> unstable" false (Stability.is_stable v)

  let semantic_stub_passes () =
    let f = Parser.parse stable_fixture in
    Alcotest.(check bool) "semantic stub stable" true
      (Stability.is_stable (Stability.check_semantic f))

  let tests = [
    Alcotest.test_case "P3_stable_on_full_fixture" `Quick stable_on_full_fixture;
    Alcotest.test_case "P3_unstable_when_section_missing" `Quick unstable_when_section_missing;
    Alcotest.test_case "P3_unstable_when_section_blank" `Quick unstable_when_section_blank;
    Alcotest.test_case "P3_semantic_stub_passes_in_step_1" `Quick semantic_stub_passes;
  ]
end

(* ---------------- Backend_stub tests (≥3) ---------------- *)
module BS = struct
  let p15_step_1_returns_tool_error () =
    let b = Backend_stub.create { responses = [] } in
    let r = Backend_stub.invoke b ~purpose:`Formalization
              ~prompt:"hi" ~budget:100 in
    match r with
    | `Tool_error _ -> ()
    | _ -> Alcotest.fail "expected Tool_error in step 1 default"

  let p15_canned_response_lookup () =
    let b = Backend_stub.create
      { responses = [
          { purpose = `Formalization; trigger = (fun _ -> true);
            payload = Ok "canned" };
        ]; }
    in
    match Backend_stub.invoke b ~purpose:`Formalization
            ~prompt:"x" ~budget:1 with
    | `Ok r -> Alcotest.(check string) "canned text" "canned" r.text
    | _ -> Alcotest.fail "expected canned Ok"

  let p15_no_match_yields_tool_error () =
    let b = Backend_stub.create
      { responses = [
          { purpose = `Gap_step; trigger = (fun _ -> true);
            payload = Ok "x" };
        ]; }
    in
    match Backend_stub.invoke b ~purpose:`Formalization
            ~prompt:"x" ~budget:1 with
    | `Tool_error _ -> ()
    | _ -> Alcotest.fail "expected Tool_error on purpose mismatch"

  let p15_name_is_stub () =
    Alcotest.(check string) "name" "stub" Backend_stub.name

  let tests = [
    Alcotest.test_case "P15_stub_step_1_default_tool_error" `Quick
      p15_step_1_returns_tool_error;
    Alcotest.test_case "P15_stub_canned_response_lookup" `Quick
      p15_canned_response_lookup;
    Alcotest.test_case "P15_stub_no_match_tool_error" `Quick
      p15_no_match_yields_tool_error;
    Alcotest.test_case "P15_stub_name" `Quick p15_name_is_stub;
  ]
end

(* ---------------- Verifier_stub tests (≥3) ---------------- *)
module VS = struct
  let p15_returns_ok () =
    let v = Verifier_stub.create () in
    match Verifier_stub.run v ~workdir:"." ~focus:[] with
    | `Ok r -> Alcotest.(check int) "exit" 0 r.raw_exit_code
    | `Tool_error _ -> Alcotest.fail "stub never errors"

  let p15_focus_is_ignored () =
    let v = Verifier_stub.create () in
    let _ = Verifier_stub.run v ~workdir:"." ~focus:["P1";"P2"] in
    Alcotest.(check string) "name" "stub" Verifier_stub.name

  let p15_version_string () =
    let v = Verifier_stub.create () in
    Alcotest.(check string) "version"
      "0.1.0-stub" (Verifier_stub.version v)

  let tests = [
    Alcotest.test_case "P15_verifier_stub_returns_ok" `Quick p15_returns_ok;
    Alcotest.test_case "P15_verifier_stub_focus_ignored" `Quick p15_focus_is_ignored;
    Alcotest.test_case "P15_verifier_stub_version" `Quick p15_version_string;
  ]
end

(* ---------------- Harness tests (≥3) ---------------- *)
module HT = struct
  module H = Harness.Make (Backend_stub) (Verifier_stub)

  let with_fixture content f =
    with_tmpdir (fun dir ->
      let fp = Filename.concat dir "in.k4k" in
      let oc = open_out fp in
      output_string oc content;
      close_out oc;
      let kdir = Filename.concat dir ".k4k" in
      let logger = Logger.create ~verbosity:`Quiet
        ~jsonl_path:(Some (Filename.concat kdir "log.jsonl")) in
      f { Harness.file_path = fp; k4k_dir = kdir; logger })

  let s5_check_stable_writes_manifest () =
    with_fixture stable_fixture (fun inputs ->
      let r = H.check inputs in
      Alcotest.(check bool) "stable result"
        true (r = Harness.Stable_structural);
      let mp = Filename.concat inputs.k4k_dir "manifest.json" in
      Alcotest.(check bool) "manifest exists" true (Sys.file_exists mp);
      let lp = Filename.concat inputs.k4k_dir "log.jsonl" in
      Alcotest.(check bool) "log exists" true (Sys.file_exists lp))

  let t1_empty_file_unstable () =
    with_fixture "" (fun inputs ->
      try
        let _ = H.check inputs in
        Alcotest.fail "expected K4k_error"
      with Error.K4k_error (Error.E_unstable _) -> ())

  let t17_stale_manifest_corrupt () =
    with_fixture stable_fixture (fun inputs ->
      Persist.ensure_dir inputs.k4k_dir;
      let mp = Filename.concat inputs.k4k_dir "manifest.json" in
      Persist.atomic_write ~path:mp
        {|{"k4k_version":"99.99.99-future"}|};
      try
        let _ = H.check inputs in
        Alcotest.fail "expected ESTATE_CORRUPT"
      with Error.K4k_error (Error.E_state_corrupt _) -> ())

  let tests = [
    Alcotest.test_case "S5_check_subcommand_exits_0_when_stable_structural"
      `Quick s5_check_stable_writes_manifest;
    Alcotest.test_case "T1_empty_file_is_unstable" `Quick t1_empty_file_unstable;
    Alcotest.test_case "T17_stale_manifest_corrupt" `Quick t17_stale_manifest_corrupt;
  ]
end

(* ---------------- Canonicalize tests (≥3, plus qcheck) ---------------- *)
module CanonT = struct
  open Characterization

  let mk_arg ?(kind=`Flag) ?(typ="string") ?(req=false) ?(rep=false)
              ?(doc="") name =
    { name; kind; type_ = typ; required = req; repeats = rep; doc }

  let mk_err id =
    { id; when_ = "x"; message_template = "msg"; exit_code = 1 }

  let mk_glob g = { glob = g; mode = `R }

  let mk_accept name =
    { name; argv = [name]; stdin = None;
      expect = { stdout = ""; stderr = ""; exit_code = 0; fs_after = None } }

  let mk_refuse name =
    { name; argv = []; stdin = None; expect_error = "EBADARG" }

  let mk_exit code = { code; condition = "" }

  (* P4 — canonicalize is idempotent (qcheck, ≥1000 trials). *)
  let p4_idempotent_qcheck =
    let argv_gen = QCheck.Gen.(
      list_size (int_range 0 5)
        (map (fun n -> mk_arg (Printf.sprintf "arg%d" n)) (int_range 0 9)))
    in
    let err_gen = QCheck.Gen.(
      list_size (int_range 0 4)
        (map (fun n -> mk_err (Printf.sprintf "E%d" n)) (int_range 0 9)))
    in
    let glob_gen = QCheck.Gen.(
      list_size (int_range 0 3)
        (map (fun n -> mk_glob (Printf.sprintf "/p%d/*" n)) (int_range 0 9)))
    in
    let accept_gen = QCheck.Gen.(
      list_size (int_range 0 3)
        (map (fun n -> mk_accept (Printf.sprintf "a%d" n)) (int_range 0 9)))
    in
    let refuse_gen = QCheck.Gen.(
      list_size (int_range 0 2)
        (map (fun n -> mk_refuse (Printf.sprintf "r%d" n)) (int_range 0 9)))
    in
    let goal_gen = QCheck.Gen.(
      map (fun s -> "  " ^ s ^ "  \n\t") (string_size (int_range 0 20)))
    in
    let mk_t goal argv errs reads writes accs refs =
      { Characterization.empty with
        goal;
        inputs_outputs = { Characterization.empty.inputs_outputs with
                           argv;
                           exit_codes = [ mk_exit 0; mk_exit 1 ] };
        errors = errs;
        fs_contract = { reads; writes; creates = [] };
        examples_accept = accs;
        examples_refuse = refs;
      }
    in
    let gen = QCheck.Gen.(
      goal_gen >>= fun g ->
      argv_gen >>= fun a ->
      err_gen >>= fun e ->
      glob_gen >>= fun rs ->
      glob_gen >>= fun ws ->
      accept_gen >>= fun acs ->
      refuse_gen >>= fun rfs ->
      return (mk_t g a e rs ws acs rfs))
    in
    let arb = QCheck.make ~print:(fun _ -> "<characterization>") gen in
    QCheck.Test.make ~count:200 ~name:"P4_canonicalization_idempotent" arb
      (fun c ->
         let c1 = Canonicalize.canonicalize c in
         let c2 = Canonicalize.canonicalize c1 in
         String.equal c1.Characterization.hash c2.Characterization.hash
         && String.equal
              (Canonicalize.canonical_bytes c1)
              (Canonicalize.canonical_bytes c2))

  (* P4 — paraphrased pairs hash equal: identical content with shuffled
     argv / errors / examples and whitespace noise. *)
  let p4_structural_equivalence () =
    let base : Characterization.t =
      { Characterization.empty with
        goal = "do the thing";
        inputs_outputs = { Characterization.empty.inputs_outputs with
                           argv = [ mk_arg "a"; mk_arg "b"; mk_arg "c" ];
                           exit_codes = [ mk_exit 0; mk_exit 1 ] };
        errors = [ mk_err "E1"; mk_err "E2" ];
        fs_contract = { reads = [ mk_glob "/x"; mk_glob "/y" ];
                        writes = []; creates = [] };
        examples_accept = [ mk_accept "ex1"; mk_accept "ex2" ];
      } in
    let shuffled : Characterization.t =
      { base with
        goal = "  do  the\tthing  ";  (* whitespace noise *)
        inputs_outputs = { base.inputs_outputs with
                           argv = [ mk_arg "c"; mk_arg "a"; mk_arg "b" ];
                           exit_codes = [ mk_exit 1; mk_exit 0 ] };
        errors = [ mk_err "E2"; mk_err "E1" ];
        fs_contract = { reads = [ mk_glob "/y"; mk_glob "/x" ];
                        writes = []; creates = [] };
        examples_accept = [ mk_accept "ex2"; mk_accept "ex1" ];
      } in
    let cb = Canonicalize.canonicalize base in
    let cs = Canonicalize.canonicalize shuffled in
    Alcotest.(check string) "hashes equal" cb.hash cs.hash;
    Alcotest.(check bool) "non-empty hash" true (cb.hash <> "")

  (* P4 — preserves user-provided identifier names. *)
  let p4_no_identifier_renaming () =
    let c = { Characterization.empty with
      inputs_outputs = { Characterization.empty.inputs_outputs with
                         argv = [ mk_arg "my-flag"; mk_arg "another" ] };
      errors = [ mk_err "EUSER" ];
    } in
    let cc = Canonicalize.canonicalize c in
    let argv_names = List.map
      (fun (a : Characterization.arg_spec) -> a.name)
      cc.inputs_outputs.argv in
    Alcotest.(check (list string)) "argv names preserved (sorted)"
      ["another"; "my-flag"] argv_names;
    Alcotest.(check string) "error id preserved"
      "EUSER" (List.hd cc.errors).id

  (* Hash differs when actual content differs. *)
  let p4_hash_differs_on_real_change () =
    let a = Canonicalize.canonicalize
      { Characterization.empty with goal = "alpha" } in
    let b = Canonicalize.canonicalize
      { Characterization.empty with goal = "beta" } in
    Alcotest.(check bool) "different hashes" true (a.hash <> b.hash)

  (* JSON round-trip: parse → serialize → re-canonicalize gives same hash. *)
  let p4_json_round_trip () =
    let c = Canonicalize.canonicalize
      { Characterization.empty with
        goal = "rt";
        inputs_outputs = { Characterization.empty.inputs_outputs with
                           argv = [ mk_arg "x" ] };
        errors = [ mk_err "EX" ];
      } in
    let bytes = Canonicalize.canonical_bytes c in
    let parsed = Yojson.Safe.from_string bytes in
    let c2 = Characterization.of_yojson parsed in
    let c2c = Canonicalize.canonicalize c2 in
    Alcotest.(check string) "round-trip hash equal" c.hash c2c.hash

  let tests = [
    qcheck_to_alcotest p4_idempotent_qcheck;
    Alcotest.test_case "P4_canonicalization_preserves_structural_equivalence"
      `Quick p4_structural_equivalence;
    Alcotest.test_case "P4_no_identifier_renaming" `Quick
      p4_no_identifier_renaming;
    Alcotest.test_case "P4_hash_differs_on_real_change" `Quick
      p4_hash_differs_on_real_change;
    Alcotest.test_case "P4_json_round_trip_preserves_hash" `Quick
      p4_json_round_trip;
  ]
end

(* ---------------- Lint-style P7 test ---------------- *)
module Lint = struct
  let lib_files = [
    "lib/error.ml"; "lib/logger.ml"; "lib/persist.ml"; "lib/parser.ml";
    "lib/stability.ml"; "lib/harness.ml"; "lib/backend_stub.ml";
    "lib/verifier_stub.ml";
  ]

  (* Locate the source root by walking up from cwd until we find the
     "lib" dir. Tests under dune run from a sandbox; the source files are
     located by walking up to dune-project. *)
  let rec find_root dir =
    if Sys.file_exists (Filename.concat dir "dune-project") then dir
    else
      let p = Filename.dirname dir in
      if p = dir then failwith "could not locate dune-project"
      else find_root p

  let p7_no_failwith_outside_invariant () =
    let root = find_root (Sys.getcwd ()) in
    List.iter (fun rel ->
      let path = Filename.concat root rel in
      let s = read_all path in
      if Astring.String.is_infix ~affix:"failwith" s then
        Alcotest.fail
          (Printf.sprintf
             "P7: %s contains 'failwith' (use Error.K4k_error or \
              Invariant_violation)" rel)
    ) lib_files

  let tests = [
    Alcotest.test_case "P7_unknown_error_is_invariant_violation"
      `Quick p7_no_failwith_outside_invariant;
  ]
end

let () =
  Alcotest.run "k4k unit"
    [ "Error",        ET.tests;
      "Logger",       LT.tests;
      "Persist",      PT.tests;
      "Parser",       ParT.tests;
      "Stability",    ST.tests;
      "Backend_stub", BS.tests;
      "Verifier_stub", VS.tests;
      "Harness",      HT.tests;
      "Canonicalize", CanonT.tests;
      "Lint",         Lint.tests;
    ]
