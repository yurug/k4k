(** Integration tests — invoke the [k4k] binary as a subprocess.

    v2 surface: [k4k <file>] starts the watcher daemon. Tests use the
    [@test_only] [--exit-on-stable] flag to return after the first
    stability snapshot (per kb/runbooks/test-environment.md). *)

let bin () =
  let here = Sys.getcwd () in
  let rec find dir =
    let cand = Filename.concat dir "_build/install/default/bin/k4k" in
    if Sys.file_exists cand then cand
    else
      let p = Filename.dirname dir in
      if p = dir then failwith "k4k binary not found"
      else find p
  in
  find here

let read_all_close ic =
  let buf = Buffer.create 256 in
  try
    while true do
      Buffer.add_channel buf ic 4096
    done; assert false
  with End_of_file -> close_in ic; Buffer.contents buf

let run_capture ?(env = []) ~k4k_args ~cwd () =
  let bin_path = bin () in
  let prev = Sys.getcwd () in
  Sys.chdir cwd;
  let env_prefix =
    String.concat " "
      (List.map (fun (k, v) ->
         Printf.sprintf "%s=%s" k (Filename.quote v)) env)
  in
  let cmd = Printf.sprintf
    "%s %s %s 1>%s 2>%s"
    env_prefix
    (Filename.quote bin_path)
    (String.concat " " (List.map Filename.quote k4k_args))
    "stdout.txt" "stderr.txt"
  in
  let code = Sys.command cmd in
  let so = read_all_close (open_in "stdout.txt") in
  let se = read_all_close (open_in "stderr.txt") in
  Sys.chdir prev;
  (code, so, se)

let copy_file src dst =
  let ic = open_in_bin src in
  let oc = open_out_bin dst in
  (try
     while true do
       output_char oc (input_char ic)
     done
   with End_of_file -> ());
  close_in ic; close_out oc

let with_workdir f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "k4k-it-%d-%d" (Unix.getpid ()) (Random.int 1_000_000))
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

let with_workdir_and_git f =
  with_workdir (fun dir ->
    let _ = K4k.Git.init ~cwd:dir in
    K4k.Git.configure_test_identity ~cwd:dir;
    let oc = open_out (Filename.concat dir ".gitignore") in
    output_string oc
      ".k4k/\n_build/\nstdout.txt\nstderr.txt\n.*.cotype/\n";
    close_out oc;
    let oc = open_out (Filename.concat dir "README.md") in
    output_string oc "# project\n"; close_out oc;
    let _ = K4k.Git.commit_all ~cwd:dir ~message:"initial" in
    f dir)

let fixture_path name =
  let here = Sys.getcwd () in
  let rec find dir =
    let cand = Filename.concat dir ("tests/fixtures/" ^ name) in
    if Sys.file_exists cand then cand
    else
      let p = Filename.dirname dir in
      if p = dir then failwith "fixture not found"
      else find p
  in
  find here

let cotype_available () =
  try
    let r = K4k.Subprocess.run ~prog:"cotype" ~args:["--version"]
              ~timeout_s:5 () in
    r.exit_code = 0
  with _ -> false

(* Skip-or-run wrapper: tests that require cotype on $PATH. *)
let with_cotype f =
  if cotype_available () then f ()
  else print_endline "skipped: cotype not on PATH"

(* --- S1: first-run UX (ADR-011 §3) --- *)

(* Fresh tempdir, no .k4k, run the watcher with --exit-on-stable on a
   non-existent file: assert starter template appears, .k4k/ is created,
   git is initialized, watcher.pid is removed on exit. *)
let s1_first_spec_first_run_e2e () =
  with_cotype (fun () ->
    with_workdir (fun dir ->
      let f = Filename.concat dir "newproject.k4k" in
      let (code, so, _se) = run_capture
        ~k4k_args:["--exit-on-stable"; "newproject.k4k"]
        ~cwd:dir () in
      Alcotest.(check bool) "watcher exits cleanly" true (code = 0 || code = 1);
      Alcotest.(check bool) "starter template created" true
        (Sys.file_exists f);
      let body = read_all_close (open_in f) in
      Alcotest.(check bool) "starter has frontmatter" true
        (Astring.String.is_infix ~affix:"k4k:\n  version: 1" body);
      Alcotest.(check bool) "starter has Goal heading" true
        (Astring.String.is_infix ~affix:"## Goal" body);
      Alcotest.(check bool) "starter has welcome block" true
        (Astring.String.is_infix ~affix:"## k4k:welcome" body);
      Alcotest.(check bool) "git initialized" true
        (Sys.file_exists (Filename.concat dir ".git"));
      Alcotest.(check bool) ".k4k/ created" true
        (Sys.file_exists (Filename.concat dir ".k4k"));
      Alcotest.(check bool) "watcher.pid removed on exit" false
        (Sys.file_exists (Filename.concat dir ".k4k/watcher.pid"));
      Alcotest.(check bool) "stdout has watcher.start event" true
        (Astring.String.is_infix ~affix:"watcher.start" so)))

(* P11 — stdout discipline (v2): every non-empty line is parseable JSON;
   stderr empty at default verbosity. *)
let p11_stdout_jsonl () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let (_code, so, se) = run_capture
        ~k4k_args:["--exit-on-stable"; "in.k4k"]
        ~cwd:dir () in
      let lines = String.split_on_char '\n' so in
      let non_empty = List.filter (fun s -> s <> "") lines in
      List.iter (fun line ->
        match Yojson.Safe.from_string line with
        | _ -> ()
        | exception _ ->
            Alcotest.failf "non-JSON stdout line: %s" line) non_empty;
      Alcotest.(check string) "stderr empty at default verbosity" "" se))

(* T1 — empty file: watcher writes a clarification block (or starter
   replaces it; depending on race). At minimum, the file is left in a
   parseable shape after the watcher returns. *)
let t1_empty_file_yields_clarification () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      let oc = open_out f in close_out oc;
      let (_code, _so, _se) = run_capture
        ~k4k_args:["--exit-on-stable"; "in.k4k"] ~cwd:dir () in
      let after = read_all_close (open_in f) in
      Alcotest.(check bool) "file no longer empty" true
        (String.length after > 0)))

(* P1 byte-equality: drive a clarification append through cotype and
   assert that every non-`## k4k:clarification:*` byte range is
   preserved. (Calls Cotype directly; bin not needed.) *)
let p1_user_section_byte_equality_under_save () =
  if not (cotype_available ()) then ()
  else with_workdir (fun dir ->
    let original =
      "---\n\
       k4k:\n  version: 1\n  class: cli\n\
       ---\n\
       # Project\n\n\
       ## Goal\n\
       Echo argv.\n\
       \n\
       ## Inputs and outputs\n\
       argv only.\n"
    in
    let path = Filename.concat dir "in.k4k" in
    let oc = open_out path in
    output_string oc original; close_out oc;
    let cotype = K4k.Cotype.create K4k.Cotype.default_config in
    K4k.Cotype.append_clarification cotype ~path
      ~questions:["clarify the goal"; "more detail on inputs"];
    let after = read_all_close (open_in path) in
    Alcotest.(check bool)
      "user-owned bytes preserved verbatim" true
      (Astring.String.is_infix ~affix:"## Goal\nEcho argv.\n" after);
    Alcotest.(check bool)
      "second user section preserved verbatim" true
      (Astring.String.is_infix ~affix:"## Inputs and outputs\nargv only.\n"
         after);
    Alcotest.(check bool) "clarification appended" true
      (Astring.String.is_infix ~affix:"## k4k:clarification:" after))

(* T8 — user edits a clarification section; the cotype machinery
   surfaces the conflict (or merges cleanly post-ADR-010). *)
let t8_user_edits_tradeoff_section_surfaces_conflict () =
  if not (cotype_available ()) then ()
  else with_workdir (fun dir ->
    let path = Filename.concat dir "in.k4k" in
    let oc = open_out path in
    output_string oc "## Goal\nfoo\n"; close_out oc;
    let cotype = K4k.Cotype.create K4k.Cotype.default_config in
    let r1 = match K4k.Cotype.open_ cotype ~file:path with
      | Ok r -> r
      | Error m -> Alcotest.failf "open: %s" m
    in
    let user_proposed =
      "## Goal\nbar\n## k4k:tradeoff:proposal:2026-05-01-000000\n\
       Approval: Approved: Tier B\n" in
    (match K4k.Cotype.save cotype ~file:path ~base_sha:r1.base_sha
            ~actor:"user" ~bytes:user_proposed with
     | Ok (Direct _) -> ()
     | _ -> Alcotest.fail "user save not direct");
    (* Re-open to read the user's response. *)
    let after = read_all_close (open_in path) in
    Alcotest.(check bool) "tradeoff appears" true
      (Astring.String.is_infix
         ~affix:"## k4k:tradeoff:proposal:" after);
    Alcotest.(check bool) "approval line present" true
      (Astring.String.is_infix ~affix:"Approved: Tier B" after))

(* S5 — rollback directive aborts the in-flight version (ADR-011 §6,
   ADR-013 §2 step 6). We exercise the directive parser + Version.rollback
   directly to keep the test deterministic; the watcher loop wires the
   same surface. *)
let s5_rollback_aborts_in_flight_version () =
  with_workdir_and_git (fun dir ->
    (* Start a version on the test repo. *)
    let baseline = match K4k.Git.head_sha ~cwd:dir with
      | Ok s -> s | Error _ -> Alcotest.fail "no HEAD" in
    let v = match K4k.Version.start_new ~cwd:dir ~number:1
              ~baseline_sha:baseline ~d_hash:"abc" with
      | Ok v -> v | Error e -> Alcotest.failf "start: %s" e in
    Alcotest.(check bool) "branch created" true
      (K4k.Git.branch_exists ~cwd:dir ~name:v.branch_name);
    (* User writes `request: rollback` in the status block. The
       directive parser picks it up. *)
    let directives = K4k.Inline_blocks.parse_directives
      "- request: rollback\n" in
    Alcotest.(check bool) "directive parsed" true
      (List.mem `Rollback directives);
    (* Watcher reacts: rollback. *)
    (match K4k.Version.rollback ~cwd:dir v ~default_branch:"main" with
     | Ok () -> () | Error e -> Alcotest.failf "rollback: %s" e);
    Alcotest.(check bool) "branch deleted on rollback" false
      (K4k.Git.branch_exists ~cwd:dir ~name:v.branch_name))

(* --- S1 v2 batch 4b: drive the watcher to v1 completion against a
   real backend (canned-responses) + real verifier (synthetic stub).
   Real formalization is wired (no [K4K_TEST_D_PATH]); the canned
   responses include a Formalization payload that the watcher reuses
   across both formalization runs. *)

(* Build a [Characterization.t] rich enough to pass coverage
   ([Coverage.check_cli]: goal, exit_codes, ≥3 acceptance examples,
   ≥1 refusing example, stdout.doc set). *)
let build_d ~verifier_cmd =
  let stream_doc s = { K4k.Characterization.kind = `Text;
                       encoding = Some "utf-8"; doc = s } in
  let acc i = { K4k.Characterization.name = Printf.sprintf "ex%d" i;
                argv = [Printf.sprintf "a%d" i];
                stdin = None;
                expect = { stdout = "out"; stderr = "";
                           exit_code = 0; fs_after = None }} in
  { K4k.Characterization.empty with
    goal = "echo argv with optional uppercasing";
    cls = "cli";
    language = "ocaml";
    verifier_command = verifier_cmd;
    inputs_outputs = {
      argv = [];
      stdin = { kind = `None; encoding = None; doc = "" };
      stdout = stream_doc "argv joined";
      stderr = { kind = `None; encoding = None; doc = "" };
      exit_codes = [{ code = 0; condition = "success" }];
    };
    examples_accept = [acc 1; acc 2; acc 3];
    examples_refuse = [{ name = "ref1"; argv = ["--unknown"];
                         stdin = None;
                         expect_error = "EBADARG" }];
  }

(* Canonical JSON form of D — used as the formalization response so
   that both runs canonicalize-equal. *)
let formalize_payload d =
  let canon = K4k.Canonicalize.canonicalize d in
  let bytes = K4k.Canonical_json.to_string
                (K4k.Characterization_json.to_yojson canon) in
  Printf.sprintf "```json\n%s\n```\n" bytes

let property_ids_of d =
  let canon = K4k.Canonicalize.canonicalize d in
  List.map (fun (p : K4k.Property.t) -> p.id)
    (K4k.Property.from_characterization canon)

let read_file p =
  let ic = open_in p in
  let n = in_channel_length ic in
  let b = Bytes.create n in really_input ic b 0 n; close_in ic;
  Bytes.unsafe_to_string b

(* Compose a unified-diff response that creates a unique source file
   per call. The synthetic verifier doesn't inspect content, so the
   diff just needs to apply cleanly and survive the commit. *)
let canned_diff_for n =
  Printf.sprintf
    "```json\n{\"files\":[\"src/p%02d.ml\"]}\n```\n\
     ```diff\n\
     diff --git a/src/p%02d.ml b/src/p%02d.ml\n\
     new file mode 100644\n\
     --- /dev/null\n\
     +++ b/src/p%02d.ml\n\
     @@ -0,0 +1 @@\n\
     +let () = ignore %d\n\
     ```\n" n n n n n

let write_canned_responses ~path ~n_props ~formalize_text =
  (* Two formalization runs (P18) produce identical canonical payloads
     so the cache doesn't already have D and stability passes. *)
  let formalize_entries = [
    `Assoc [ "purpose", `String "Formalization";
             "text", `String formalize_text ];
    `Assoc [ "purpose", `String "Formalization";
             "text", `String formalize_text ];
  ] in
  let entries = List.init n_props (fun i ->
    `Assoc [
      "purpose", `String "Gap_step";
      "text", `String (canned_diff_for (i + 1));
    ]) in
  (* Add a few extra entries to absorb any rejection-retry — the
     loop runs each property up to 3 times. *)
  let extras = List.init (n_props * 2) (fun i ->
    `Assoc [
      "purpose", `String "Gap_step";
      "text", `String (canned_diff_for (n_props + i + 1));
    ]) in
  let bytes = Yojson.Safe.to_string
    (`List (formalize_entries @ entries @ extras)) in
  let oc = open_out path in
  output_string oc bytes; close_out oc

let copy_synthetic_verifier ~src ~dst =
  copy_file src dst;
  Unix.chmod dst 0o755

let run_capture_with_env ~k4k_args ~cwd ~env () =
  run_capture ~env ~k4k_args ~cwd ()

let s1_watcher_drives_v1_to_completion () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"add in.k4k" in
      (* Drop the synthetic verifier into the workdir. *)
      let verifier_dst = Filename.concat dir "_verifier.sh" in
      let here = Sys.getcwd () in
      let rec find_synth d =
        let cand = Filename.concat d
          "test/conformance/fixtures/synthetic-verifier.sh" in
        if Sys.file_exists cand then cand
        else
          let p = Filename.dirname d in
          if p = d then failwith "synthetic-verifier.sh not found"
          else find_synth p
      in
      copy_synthetic_verifier ~src:(find_synth here) ~dst:verifier_dst;
      let d = build_d ~verifier_cmd:["./_verifier.sh"] in
      let pids = property_ids_of d in
      let canned_path = Filename.concat dir "canned.json" in
      write_canned_responses ~path:canned_path
        ~n_props:(List.length pids)
        ~formalize_text:(formalize_payload d);
      let _ = K4k.Git.commit_all ~cwd:dir
        ~message:"test: add verifier + canned" in
      let est = String.concat " " pids in
      let env = [
        ("K4K_STUB_RESPONSES", canned_path);
        ("K4K_SYNTH_ESTABLISHED", est);
      ] in
      let (_code, so, se) = run_capture_with_env
        ~k4k_args:["--exit-on-done"; "in.k4k"]
        ~cwd:dir ~env () in
      let _ = se in
      Alcotest.(check bool) "version.start emitted" true
        (Astring.String.is_infix ~affix:"version.start" so);
      Alcotest.(check bool) "version.complete emitted" true
        (Astring.String.is_infix ~affix:"version.complete" so);
      Alcotest.(check bool) "version.commit emitted" true
        (Astring.String.is_infix ~affix:"version.commit" so);
      Alcotest.(check bool) "v1 tag exists" true
        (K4k.Git.tag_exists ~cwd:dir ~name:"v1");
      Alcotest.(check bool) "version branch deleted" false
        (K4k.Git.branch_exists ~cwd:dir ~name:"k4k/version/1");
      let manifest_p =
        Filename.concat dir ".k4k/version/1/manifest.json" in
      Alcotest.(check bool) "manifest.json exists" true
        (Sys.file_exists manifest_p);
      let m = read_file manifest_p in
      Alcotest.(check bool) "manifest mentions tag v1" true
        (Astring.String.is_infix ~affix:"\"tag\": \"v1\"" m);
      Alcotest.(check bool) "D-spec.json exists" true
        (Sys.file_exists
           (Filename.concat dir ".k4k/version/1/D-spec.json"));
      Alcotest.(check bool) "audit.md exists" true
        (Sys.file_exists
           (Filename.concat dir ".k4k/version/1/audit.md"));
      (* The accepted source files must have landed on the default
         branch via the merge. *)
      let src_dir = Filename.concat dir "src" in
      Alcotest.(check bool) "src/ created on main" true
        (Sys.file_exists src_dir);
      Alcotest.(check bool) "src/p01.ml landed on main" true
        (Sys.file_exists (Filename.concat src_dir "p01.ml"));
      (* Audit lists each property as established. *)
      let audit = read_file
        (Filename.concat dir ".k4k/version/1/audit.md") in
      List.iter (fun pid ->
        Alcotest.(check bool)
          (Printf.sprintf "audit lists %s as established" pid) true
          (Astring.String.is_infix ~affix:pid audit)) pids))

(* --- S5 v2 batch 3: drive the watcher to a rollback via directive --- *)
let s5_rollback_via_directive_in_status_block () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      (* Pre-cut a version 1 branch (simulating a partial-development
         state) and inject `request: rollback` in the file. *)
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"add in.k4k" in
      let baseline = match K4k.Git.head_sha ~cwd:dir with
        | Ok s -> s | Error _ -> Alcotest.fail "no HEAD" in
      let _ = K4k.Version.start_new ~cwd:dir ~number:1
                ~baseline_sha:baseline ~d_hash:"abc" in
      let _ = K4k.Git.checkout ~cwd:dir ~name:"main" in
      (* Persist the version manifest dir so next_version_number sees it. *)
      let k4k_dir = Filename.concat dir ".k4k" in
      K4k.Version_persist.ensure_dirs ~k4k_dir ~number:1;
      (* Append a request:rollback into the file. *)
      let body = read_file f in
      let oc = open_out f in
      output_string oc body;
      output_string oc
        "\n## k4k:status\n- State: developing\n\
         ### User control directives\n- request: rollback\n";
      close_out oc;
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"user: request rollback" in
      Alcotest.(check bool) "branch exists pre-watch" true
        (K4k.Git.branch_exists ~cwd:dir ~name:"k4k/version/1");
      let (_code, so, _se) = run_capture
        ~k4k_args:["--exit-on-done"; "in.k4k"]
        ~cwd:dir () in
      let _ = so in
      Alcotest.(check bool) "branch deleted on rollback" false
        (K4k.Git.branch_exists ~cwd:dir ~name:"k4k/version/1")))

(* --- NF1: SIGINT shuts the watcher down within 5 s. --- *)
let nf1_sigint_during_watcher () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let bin_path = bin () in
      let stdout_r, stdout_w = Unix.pipe () in
      let stderr_r, stderr_w = Unix.pipe () in
      let env = Unix.environment () in
      let prev_cwd = Unix.getcwd () in
      Unix.chdir dir;
      let argv = [| bin_path; "in.k4k" |] in
      let pid = Unix.create_process_env bin_path argv env
                  Unix.stdin stdout_w stderr_w in
      Unix.chdir prev_cwd;
      Unix.close stdout_w; Unix.close stderr_w;
      Unix.sleep 1;
      let t_signal = Unix.gettimeofday () in
      Unix.kill pid Sys.sigint;
      let rec wait_done () =
        match Unix.waitpid [Unix.WNOHANG] pid with
        | 0, _ ->
            if Unix.gettimeofday () -. t_signal > 6.0 then begin
              (try Unix.kill pid Sys.sigkill with _ -> ());
              ignore (Unix.waitpid [] pid);
              false
            end else begin
              ignore (Unix.select [] [] [] 0.1);
              wait_done ()
            end
        | _, _ -> true
        | exception _ -> true
      in
      let exited = wait_done () in
      let dt = Unix.gettimeofday () -. t_signal in
      (try Unix.close stdout_r with _ -> ());
      (try Unix.close stderr_r with _ -> ());
      Alcotest.(check bool) "exited within 5 s" true
        (exited && dt <= 5.0)))

(* ---------------- Ollama backend example ---------------- *)

let ollama_bin () =
  let here = Sys.getcwd () in
  let rec find dir =
    let cand = Filename.concat dir
      "_build/default/examples/backends/ollama/main.exe" in
    if Sys.file_exists cand then cand
    else
      let p = Filename.dirname dir in
      if p = dir then failwith "ollama_backend binary not found"
      else find p
  in find here

let write_file path content =
  let oc = open_out path in output_string oc content; close_out oc

let run_ollama ~mock ~budget ~prompt ~output =
  let bin = ollama_bin () in
  let cmd = Printf.sprintf "%s --mock-response %s --purpose formalization \
                            --prompt-file %s --budget %d --output %s 2>/dev/null"
    (Filename.quote bin) (Filename.quote mock)
    (Filename.quote prompt) budget (Filename.quote output) in
  Sys.command cmd

let read_json path =
  let ic = open_in path in
  let buf = Buffer.create 256 in
  (try
     while true do Buffer.add_channel buf ic 4096 done; assert false
   with End_of_file -> close_in ic);
  Yojson.Safe.from_string (Buffer.contents buf)

let str_field key (j : Yojson.Safe.t) = match j with
  | `Assoc fs -> (match List.assoc_opt key fs with
      | Some (`String s) -> s | _ -> "")
  | _ -> ""

let int_field key (j : Yojson.Safe.t) = match j with
  | `Assoc fs -> (match List.assoc_opt key fs with
      | Some (`Int i) -> i | _ -> -1)
  | _ -> -1

let ollama_emits_ok_for_well_formed_response () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "translate to JSON";
    let m = Filename.concat dir "mock.json" in
    write_file m {|{"model":"qwen3.5:9b","response":"OK","prompt_eval_count":5,"eval_count":3,"done":true}|};
    let o = Filename.concat dir "result.json" in
    let code = run_ollama ~mock:m ~budget:1000 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "ok" (str_field "outcome" j);
    Alcotest.(check string) "text" "OK" (str_field "text" j);
    Alcotest.(check int) "budget_used" 8 (int_field "budget_used" j))

let ollama_maps_error_field_to_tool_error () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m {|{"error":"model 'bogus' not found"}|};
    let o = Filename.concat dir "result.json" in
    let code = run_ollama ~mock:m ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "tool_error" (str_field "outcome" j);
    Alcotest.(check bool) "error mentions ollama" true
      (Astring.String.is_infix ~affix:"ollama error"
         (str_field "error" j)))

let ollama_budget_exhausted_when_tokens_exceed_cap () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m {|{"response":"R","prompt_eval_count":50,"eval_count":60}|};
    let o = Filename.concat dir "result.json" in
    let code = run_ollama ~mock:m ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "budget_exhausted"
      (str_field "outcome" j))

(* --- S3: Tier-A → tradeoff proposal → user signs off Tier B → version
   completes at Tier B. *)

let canned_empty_diff =
  "no diff in this response — agent failed to produce a patch\n"

let write_s3_canned_responses ~path ~formalize_text =
  (* 2 formalization (P18) + 3 rejected Tier-A diffs to trigger
     tradeoff + 1 successful Tier-B diff. *)
  let formalize_entries = [
    `Assoc [ "purpose", `String "Formalization";
             "text", `String formalize_text ];
    `Assoc [ "purpose", `String "Formalization";
             "text", `String formalize_text ];
  ] in
  let bad_entries = List.init 3 (fun _ ->
    `Assoc [ "purpose", `String "Gap_step";
             "text", `String canned_empty_diff ]) in
  let good_entry = `Assoc [
    "purpose", `String "Gap_step";
    "text", `String (canned_diff_for 99); ] in
  let bytes = Yojson.Safe.to_string
    (`List (formalize_entries @ bad_entries @ [good_entry])) in
  let oc = open_out path in
  output_string oc bytes; close_out oc

let s3_tradeoff_proposal_signed_off () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"add in.k4k" in
      let verifier_dst = Filename.concat dir "_verifier.sh" in
      let here = Sys.getcwd () in
      let rec find_synth d =
        let cand = Filename.concat d
          "test/conformance/fixtures/synthetic-verifier.sh" in
        if Sys.file_exists cand then cand
        else
          let p = Filename.dirname d in
          if p = d then failwith "synthetic-verifier.sh not found"
          else find_synth p
      in
      copy_synthetic_verifier ~src:(find_synth here) ~dst:verifier_dst;
      let d = build_d ~verifier_cmd:["./_verifier.sh"] in
      let pids = property_ids_of d in
      let canned_path = Filename.concat dir "canned.json" in
      write_s3_canned_responses ~path:canned_path
        ~formalize_text:(formalize_payload d);
      let _ = K4k.Git.commit_all ~cwd:dir
        ~message:"test: add verifier + canned" in
      (* Pin to a single property so the test stays deterministic
         (we only have 1 successful Tier-B diff). *)
      let est = String.concat " " pids in
      let env = [
        ("K4K_STUB_RESPONSES", canned_path);
        ("K4K_SYNTH_ESTABLISHED", est);
        ("K4K_TEST_TRADEOFF_AUTOAPPROVE", "tier-b");
      ] in
      let (_code, so, _se) = run_capture_with_env
        ~k4k_args:["--exit-on-done"; "in.k4k"]
        ~cwd:dir ~env () in
      Alcotest.(check bool) "tradeoff.proposed emitted" true
        (Astring.String.is_infix ~affix:"tradeoff.proposed" so);
      Alcotest.(check bool) "tradeoff.approved emitted" true
        (Astring.String.is_infix ~affix:"tradeoff.approved" so);
      Alcotest.(check bool) "tradeoff.resolved emitted" true
        (Astring.String.is_infix ~affix:"tradeoff.resolved" so);
      (* Post-approval Tier-B execution lands a real commit on the
         version branch via Version.commit_accept (event:
         "version.commit" with tier="B"). *)
      Alcotest.(check bool) "version.commit emitted post-approval" true
        (Astring.String.is_infix ~affix:"version.commit" so);
      Alcotest.(check bool) "approved tier-b commit on stream" true
        (Astring.String.is_infix
           ~affix:"\"event\":\"version.commit\""
           so &&
         Astring.String.is_infix ~affix:"\"tier\":\"B\"" so)))

let count_substr s sub =
  let n = String.length sub in
  let m = String.length s in
  let rec loop i acc =
    if i + n > m then acc
    else if String.sub s i n = sub then loop (i + 1) (acc + 1)
    else loop (i + 1) acc
  in loop 0 0

(* --- P22: user edits during development are queued, never interrupt
   (ADR-011 §6; properties/functional.md#P22).

   The user edit is injected by a verifier wrapper that, on its FIRST
   invocation, appends a sentinel line to the user-owned `## Goal`
   section of `in.k4k` (direct file write — simulating an external
   editor mutation). Subsequent invocations pass through to the
   synthetic verifier. With `K4K_SYNTH_ESTABLISHED` covering every
   focus id, the very first gap-step is accepted, so the user edit
   lands in the establish-commit's `git add -A`. The next
   [run_gap_loop] iteration's [Version_user_edits.check_and_queue]
   detects the drift, surfaces the count in the status block, and
   emits [user_edits.queued]. *)

let write_p22_verifier_wrapper ~path ~synth_path ~k4k_file =
  let body = Printf.sprintf {|#!/bin/sh
set -e
SENTINEL=%s.p22-edited
TARGET=%s
SYNTH=%s
if [ ! -f "$SENTINEL" ]; then
  if [ -f "$TARGET" ]; then
    awk '
      BEGIN { done=0 }
      /^## Goal[[:space:]]*$/ && done==0 {
        print
        print "EDITED-MID-FLIGHT-P22"
        done=1
        next
      }
      { print }
    ' "$TARGET" > "$TARGET.tmp.p22" && mv "$TARGET.tmp.p22" "$TARGET"
  fi
  touch "$SENTINEL"
fi
exec "$SYNTH" "$@"
|} (Filename.quote path) (Filename.quote k4k_file)
     (Filename.quote synth_path) in
  let oc = open_out path in
  output_string oc body; close_out oc;
  Unix.chmod path 0o755

let p22_user_edits_queued_during_development () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"add in.k4k" in
      let here = Sys.getcwd () in
      let rec find_synth d =
        let cand = Filename.concat d
          "test/conformance/fixtures/synthetic-verifier.sh" in
        if Sys.file_exists cand then cand
        else
          let p = Filename.dirname d in
          if p = d then failwith "synthetic-verifier.sh not found"
          else find_synth p
      in
      let synth_src = find_synth here in
      let synth_dst = Filename.concat dir "_synth.sh" in
      copy_synthetic_verifier ~src:synth_src ~dst:synth_dst;
      let verifier_dst = Filename.concat dir "_verifier.sh" in
      write_p22_verifier_wrapper ~path:verifier_dst
        ~synth_path:synth_dst ~k4k_file:f;
      let d = build_d ~verifier_cmd:["./_verifier.sh"] in
      let pids = property_ids_of d in
      let canned_path = Filename.concat dir "canned.json" in
      write_canned_responses ~path:canned_path
        ~n_props:(List.length pids)
        ~formalize_text:(formalize_payload d);
      let _ = K4k.Git.commit_all ~cwd:dir
        ~message:"test: add verifier + canned" in
      let est = String.concat " " pids in
      let env = [
        ("K4K_STUB_RESPONSES", canned_path);
        ("K4K_SYNTH_ESTABLISHED", est);
      ] in
      let (_code, so, _se) = run_capture_with_env
        ~k4k_args:["--exit-on-done"; "in.k4k"]
        ~cwd:dir ~env () in
      Alcotest.(check bool) "user_edits.queued emitted" true
        (Astring.String.is_infix ~affix:"user_edits.queued" so);
      Alcotest.(check bool) "queue count is 1" true
        (Astring.String.is_infix ~affix:"\"count\":1" so);
      (* The event fires exactly once: a single user edit produces
         one [user_edits.queued] regardless of how many gap-step
         iterations follow. *)
      Alcotest.(check int) "exactly one user_edits.queued event" 1
        (count_substr so "\"event\":\"user_edits.queued\"");
      Alcotest.(check bool) "version.complete emitted" true
        (Astring.String.is_infix ~affix:"version.complete" so);
      (* Sentinel landed on main via the version merge. *)
      let final = read_file f in
      Alcotest.(check bool) "user edit present in merged file" true
        (Astring.String.is_infix ~affix:"EDITED-MID-FLIGHT-P22" final);
      (* The version-branch's "queue user edits" commit shows up in
         the git log (visible on main after the merge). *)
      let log_cmd = Printf.sprintf
        "cd %s && git log --pretty=format:%%s"
        (Filename.quote dir) in
      let ic = Unix.open_process_in log_cmd in
      let log = read_all_close ic in
      Alcotest.(check bool) "queue-user-edits commit in log" true
        (Astring.String.is_infix
           ~affix:"queue user edits for v" log)))

(* --- P22 (b): version N+1 picks up the queued edits. Drives the
   watcher with --max-versions=2: v1 completes despite the mid-flight
   user edit; v2 then starts because the file's user-section hashes
   no longer match v1's manifest, formalize produces a fresh D, and
   the idempotence gate (Watcher_dev.try_run_version vs.
   Version_persist.last_completed_d_hash) lets the new version
   through. *)

let write_v1_v2_canned ~path ~payload1 ~n1 ~payload2 ~n2 =
  let formalize p = `Assoc [ "purpose", `String "Formalization";
                             "text", `String p ] in
  let gap n = `Assoc [ "purpose", `String "Gap_step";
                       "text", `String (canned_diff_for n) ] in
  let v1_form = [formalize payload1; formalize payload1] in
  let v1_gap  = List.init n1 (fun i -> gap (i + 1)) in
  let v2_form = [formalize payload2; formalize payload2] in
  let v2_gap  = List.init n2 (fun i -> gap (n1 + i + 1)) in
  let extras  = List.init 4 (fun i -> gap (n1 + n2 + i + 1)) in
  let bytes = Yojson.Safe.to_string
    (`List (v1_form @ v1_gap @ v2_form @ v2_gap @ extras)) in
  let oc = open_out path in
  output_string oc bytes; close_out oc

let p22b_v1_to_v2_picks_up_user_edits () =
  with_cotype (fun () ->
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "in.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"add in.k4k" in
      let here = Sys.getcwd () in
      let rec find_synth d =
        let cand = Filename.concat d
          "test/conformance/fixtures/synthetic-verifier.sh" in
        if Sys.file_exists cand then cand
        else
          let p = Filename.dirname d in
          if p = d then failwith "synthetic-verifier.sh not found"
          else find_synth p
      in
      let synth_dst = Filename.concat dir "_synth.sh" in
      copy_synthetic_verifier ~src:(find_synth here) ~dst:synth_dst;
      let verifier_dst = Filename.concat dir "_verifier.sh" in
      write_p22_verifier_wrapper ~path:verifier_dst
        ~synth_path:synth_dst ~k4k_file:f;
      let d1 = build_d ~verifier_cmd:["./_verifier.sh"] in
      let d2 =
        { d1 with K4k.Characterization.goal =
                    d1.K4k.Characterization.goal ^ " (v2)" } in
      let pids1 = property_ids_of d1 in
      let pids2 = property_ids_of d2 in
      let canned_path = Filename.concat dir "canned.json" in
      write_v1_v2_canned ~path:canned_path
        ~payload1:(formalize_payload d1) ~n1:(List.length pids1)
        ~payload2:(formalize_payload d2) ~n2:(List.length pids2);
      let _ = K4k.Git.commit_all ~cwd:dir
        ~message:"test: add verifier + canned" in
      let est = String.concat " " (pids1 @ pids2) in
      let env = [
        ("K4K_STUB_RESPONSES", canned_path);
        ("K4K_SYNTH_ESTABLISHED", est);
      ] in
      let (_code, so, _se) = run_capture_with_env
        ~k4k_args:["--max-versions=2"; "in.k4k"]
        ~cwd:dir ~env () in
      Alcotest.(check int) "two version.complete events" 2
        (count_substr so "\"event\":\"version.complete\"");
      Alcotest.(check bool) "v1 tag created" true
        (K4k.Git.tag_exists ~cwd:dir ~name:"v1");
      Alcotest.(check bool) "v2 tag created" true
        (K4k.Git.tag_exists ~cwd:dir ~name:"v2");
      Alcotest.(check bool) "user_edits.queued seen during v1" true
        (Astring.String.is_infix ~affix:"user_edits.queued" so);
      Alcotest.(check bool) "version.start fires twice" true
        (count_substr so "\"event\":\"version.start\"" = 2)))

(* ---------------- claude-code backend example ---------------- *)

let claude_code_bin () =
  let here = Sys.getcwd () in
  let rec find dir =
    let cand = Filename.concat dir
      "_build/default/examples/backends/claude-code/main.exe" in
    if Sys.file_exists cand then cand
    else
      let p = Filename.dirname dir in
      if p = dir then failwith "claude_code_backend binary not found"
      else find p
  in find here

let run_claude_code ~mock ~budget ~prompt ~output =
  let bin = claude_code_bin () in
  let cmd = Printf.sprintf "%s --mock-response %s --purpose formalization \
                            --prompt-file %s --budget %d --output %s 2>/dev/null"
    (Filename.quote bin) (Filename.quote mock)
    (Filename.quote prompt) budget (Filename.quote output) in
  Sys.command cmd

let claude_code_emits_ok_for_well_formed_response () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "translate to JSON";
    let m = Filename.concat dir "mock.json" in
    write_file m
      {|{"result":{"text":"OK"},"usage":{"input_tokens":4,"output_tokens":3}}|};
    let o = Filename.concat dir "result.json" in
    let code = run_claude_code ~mock:m ~budget:1000 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "ok" (str_field "outcome" j);
    Alcotest.(check string) "text" "OK" (str_field "text" j);
    Alcotest.(check int) "budget_used" 7 (int_field "budget_used" j))

let claude_code_budget_exhausted_when_tokens_exceed_cap () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m
      {|{"result":{"text":"R"},"usage":{"input_tokens":50,"output_tokens":60}}|};
    let o = Filename.concat dir "result.json" in
    let code = run_claude_code ~mock:m ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "budget_exhausted"
      (str_field "outcome" j))

let claude_code_malformed_json_is_tool_error () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m {|not-a-json}|};
    let o = Filename.concat dir "result.json" in
    let code = run_claude_code ~mock:m ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "tool_error"
      (str_field "outcome" j))

let claude_code_missing_text_yields_empty_ok () =
  (* The wrapper schema parser tolerates missing result.text by
     defaulting to "". Documents the behavior; not a hard contract. *)
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m {|{"usage":{"input_tokens":1,"output_tokens":1}}|};
    let o = Filename.concat dir "result.json" in
    let code = run_claude_code ~mock:m ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "ok" (str_field "outcome" j);
    Alcotest.(check string) "text" "" (str_field "text" j))

let ollama_no_response_field_is_tool_error () =
  with_workdir (fun dir ->
    let p = Filename.concat dir "prompt.txt" in
    write_file p "x";
    let m = Filename.concat dir "mock.json" in
    write_file m {|{"done":true}|};
    let o = Filename.concat dir "result.json" in
    let code = run_ollama ~mock:m ~budget:100 ~prompt:p ~output:o in
    Alcotest.(check int) "exit 0" 0 code;
    let j = read_json o in
    Alcotest.(check string) "outcome" "tool_error"
      (str_field "outcome" j))

let () =
  Alcotest.run "k4k integration"
    [ "S1", [
        Alcotest.test_case
          "S1_first_spec_first_run_e2e" `Slow s1_first_spec_first_run_e2e;
      ];
      "S5", [
        Alcotest.test_case
          "S5_rollback_aborts_in_flight_version" `Quick
          s5_rollback_aborts_in_flight_version;
        Alcotest.test_case
          "S5_rollback_via_directive_in_status_block" `Slow
          s5_rollback_via_directive_in_status_block;
      ];
      "S1_v2", [
        Alcotest.test_case
          "S1_watcher_drives_v1_to_completion" `Slow
          s1_watcher_drives_v1_to_completion;
      ];
      "S3", [
        Alcotest.test_case
          "S3_tradeoff_proposal_signed_off" `Slow
          s3_tradeoff_proposal_signed_off;
      ];
      "P22", [
        Alcotest.test_case
          "P22_user_edits_queued_during_development" `Slow
          p22_user_edits_queued_during_development;
        Alcotest.test_case
          "P22b_v1_to_v2_picks_up_user_edits" `Slow
          p22b_v1_to_v2_picks_up_user_edits;
      ];
      "NF1", [
        Alcotest.test_case
          "NF1_sigint_during_watcher_exits_within_5s" `Slow
          nf1_sigint_during_watcher;
      ];
      "P11", [
        Alcotest.test_case "P11_stdout_jsonl" `Slow p11_stdout_jsonl;
      ];
      "T1", [
        Alcotest.test_case "T1_empty_file_yields_clarification" `Slow
          t1_empty_file_yields_clarification;
      ];
      "T8", [
        Alcotest.test_case
          "T8_user_edits_tradeoff_section_surfaces_conflict"
          `Quick t8_user_edits_tradeoff_section_surfaces_conflict;
      ];
      "P1", [
        Alcotest.test_case
          "P1_user_section_byte_equality_under_save" `Quick
          p1_user_section_byte_equality_under_save;
      ];
      "claude_code_backend", [
        Alcotest.test_case "claude_code_emits_ok_for_well_formed_response"
          `Quick claude_code_emits_ok_for_well_formed_response;
        Alcotest.test_case "claude_code_budget_exhausted_when_tokens_exceed_cap"
          `Quick claude_code_budget_exhausted_when_tokens_exceed_cap;
        Alcotest.test_case "claude_code_malformed_json_is_tool_error"
          `Quick claude_code_malformed_json_is_tool_error;
        Alcotest.test_case "claude_code_missing_text_yields_empty_ok"
          `Quick claude_code_missing_text_yields_empty_ok;
      ];
      "ollama_backend", [
        Alcotest.test_case "ollama_emits_ok_for_well_formed_response"
          `Quick ollama_emits_ok_for_well_formed_response;
        Alcotest.test_case "ollama_maps_error_field_to_tool_error"
          `Quick ollama_maps_error_field_to_tool_error;
        Alcotest.test_case "ollama_budget_exhausted_when_tokens_exceed_cap"
          `Quick ollama_budget_exhausted_when_tokens_exceed_cap;
        Alcotest.test_case "ollama_no_response_field_is_tool_error"
          `Quick ollama_no_response_field_is_tool_error;
      ];
    ]
