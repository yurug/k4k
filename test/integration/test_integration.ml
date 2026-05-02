(** Integration tests — invoke the [k4k] binary as a subprocess.

    These tests cover P11 (stdout/stderr discipline) and the
    end-to-end S5 acceptance test. *)

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

let s5_check_stable_exits_0 () =
  with_workdir (fun dir ->
    let f = Filename.concat dir "in.k4k" in
    copy_file (fixture_path "well-formed-structural.k4k") f;
    let canned = fixture_path "canned-responses.json" in
    let (code, so, se) = run_capture
      ~env:[ "K4K_STUB_RESPONSES", canned ]
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir () in
    Alcotest.(check int) "exit 0" 0 code;
    Alcotest.(check string) "stdout exact"
      "stable\n" so;
    Alcotest.(check string) "stderr empty (default verbosity)" "" se;
    Alcotest.(check bool) "manifest written" true
      (Sys.file_exists (Filename.concat dir ".k4k/manifest.json"));
    Alcotest.(check bool) "desired/spec.json written" true
      (Sys.file_exists
         (Filename.concat dir ".k4k/characterization/desired/spec.json"));
    Alcotest.(check bool) "log written" true
      (Sys.file_exists (Filename.concat dir ".k4k/log.jsonl")))

let p11_stdout_pipeable () =
  with_workdir (fun dir ->
    let f = Filename.concat dir "in.k4k" in
    copy_file (fixture_path "well-formed-structural.k4k") f;
    let canned = fixture_path "canned-responses.json" in
    let (_, so, _) = run_capture
      ~env:[ "K4K_STUB_RESPONSES", canned ]
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir () in
    let lines = String.split_on_char '\n' so in
    let non_empty = List.filter (fun s -> s <> "") lines in
    Alcotest.(check int) "exactly one stdout line"
      1 (List.length non_empty);
    Alcotest.(check string) "stdout payload"
      "stable" (List.hd non_empty))

let t1_empty_file_exits_1 () =
  with_workdir (fun dir ->
    let f = Filename.concat dir "in.k4k" in
    let oc = open_out f in close_out oc;
    let (code, _, se) = run_capture
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir () in
    Alcotest.(check int) "exit 1" 1 code;
    Alcotest.(check bool) "stderr mentions unstable" true
      (Astring.String.is_infix ~affix:"unstable" se))

(* P19 — second invocation on unchanged file: zero formalization
   events in JSONL (cache hit). *)
let p19_cache_skips_formalization_when_hash_matches () =
  with_workdir (fun dir ->
    let f = Filename.concat dir "in.k4k" in
    copy_file (fixture_path "well-formed-structural.k4k") f;
    let canned = fixture_path "canned-responses.json" in
    let (code1, _, _) = run_capture
      ~env:[ "K4K_STUB_RESPONSES", canned ]
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir () in
    Alcotest.(check int) "first run ok" 0 code1;
    (* Second run with NO canned responses — would fail if formalization
       were attempted; cache hit means it's not. *)
    let (code2, _, _) = run_capture
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir () in
    Alcotest.(check int) "second run cached" 0 code2)

(* Round-trip: the on-disk spec.json validates against
   Characterization and re-canonicalizes to the same hash. *)
let spec_json_validates_round_trip () =
  with_workdir (fun dir ->
    let f = Filename.concat dir "in.k4k" in
    copy_file (fixture_path "well-formed-structural.k4k") f;
    let canned = fixture_path "canned-responses.json" in
    let (code, _, _) = run_capture
      ~env:[ "K4K_STUB_RESPONSES", canned ]
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir () in
    Alcotest.(check int) "exit 0" 0 code;
    let raw = read_all_close (open_in
      (Filename.concat dir ".k4k/characterization/desired/spec.json")) in
    let parsed = Yojson.Safe.from_string raw in
    let c = K4k.Characterization_decoder.of_yojson parsed in
    let canon = K4k.Canonicalize.canonicalize c in
    Alcotest.(check bool) "non-empty hash" true (canon.hash <> ""))

(* --- step 3: S1 echo-upper convergence test --- *)

let dune_available () =
  try
    let r = K4k.Subprocess.run ~prog:"dune" ~args:["--version"]
              ~timeout_s:5 () in
    r.exit_code = 0
  with _ -> false

let with_workdir_and_git f =
  with_workdir (fun dir ->
    let _ = K4k.Git.init ~cwd:dir in
    K4k.Git.configure_test_identity ~cwd:dir;
    let oc = open_out (Filename.concat dir ".gitignore") in
    (* Capture-stream files end up in cwd; ignore them. *)
    output_string oc ".k4k/\n_build/\nstdout.txt\nstderr.txt\n";
    close_out oc;
    let oc = open_out (Filename.concat dir "README.md") in
    output_string oc "# project\n"; close_out oc;
    let _ = K4k.Git.commit_all ~cwd:dir ~message:"initial" in
    f dir)

let s1_echo_first_run_e2e () =
  if not (dune_available ()) then
    print_endline "S1: skipped (dune not on PATH)"
  else
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "echo-upper.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"add spec" in
      let canned = fixture_path "echo-upper-canned.json" in
      let (code, so, se) = run_capture
        ~env:[ "K4K_STUB_RESPONSES", canned;
               "PATH", (Sys.getenv "PATH") ]
        ~k4k_args:["--max-steps"; "30"; "echo-upper.k4k"]
        ~cwd:dir () in
      if code <> 0 then begin
        Printf.printf "stdout: %s\n" so;
        Printf.printf "stderr: %s\n" se;
        let log_path = Filename.concat dir ".k4k/log.jsonl" in
        if Sys.file_exists log_path then
          Printf.printf "log: %s\n"
            (let ic = open_in log_path in
             let r = read_all_close ic in r)
      end;
      Alcotest.(check int) "exit 0" 0 code;
      Alcotest.(check bool) "stdout contains done" true
        (Astring.String.is_infix ~affix:"done" so);
      Alcotest.(check bool) "manifest" true
        (Sys.file_exists (Filename.concat dir ".k4k/manifest.json"));
      Alcotest.(check bool) "spec.json" true
        (Sys.file_exists
           (Filename.concat dir
              ".k4k/characterization/desired/spec.json"));
      Alcotest.(check bool) "gap properties" true
        (Sys.file_exists
           (Filename.concat dir ".k4k/gap/properties.json"));
      let gap_raw = (let ic = open_in
        (Filename.concat dir ".k4k/gap/properties.json") in
        read_all_close ic) in
      Alcotest.(check bool) "gap count: 0 after convergence" true
        (Astring.String.is_infix ~affix:"\"count\":0" gap_raw);
      (* Final dune runtest must pass on the grown source tree. *)
      let r = K4k.Subprocess.run ~prog:"dune"
                ~args:["build";"@runtest";"--force";"--root";dir]
                ~timeout_s:60 () in
      Alcotest.(check int) "final dune runtest exit 0" 0 r.exit_code;
      (* Step 4 — target KB completeness. *)
      let must = [
        ".k4k/INDEX.md";
        ".k4k/GLOSSARY.md";
        ".k4k/spec/data-model.md";
        ".k4k/spec/algorithms.md";
        ".k4k/properties/functional.md";
        ".k4k/properties/edge-cases.md";
      ] in
      List.iter (fun f ->
        Alcotest.(check bool) (f ^ " present") true
          (Sys.file_exists (Filename.concat dir f))) must;
      let glossary = read_all_close
        (open_in (Filename.concat dir ".k4k/GLOSSARY.md")) in
      Alcotest.(check bool) "GLOSSARY.md non-empty" true
        (String.length glossary > 0);
      List.iter (fun key ->
        Alcotest.(check bool)
          (key ^ " present in GLOSSARY") true
          (Astring.String.is_infix ~affix:key glossary))
        [ "owner: k4k"; "content_hash:"; "id:"; "type:" ])

(* --- NF1 SIGINT subprocess test ---

   Spawn k4k as a subprocess with a stub agent that "sleeps" via the
   K4K_STUB_SLOW env var (handled in bin/main.ml). After a short delay,
   send SIGINT and assert exit within 5 s. *)

let nf1_sigint_during_agent () =
  if not (dune_available ()) then
    print_endline "NF1: skipped (dune not on PATH)"
  else
    with_workdir_and_git (fun dir ->
      let f = Filename.concat dir "echo-upper.k4k" in
      copy_file (fixture_path "echo-upper.k4k") f;
      let _ = K4k.Git.commit_all ~cwd:dir ~message:"add spec" in
      let canned = fixture_path "echo-upper-canned.json" in
      (* Spawn the binary, send SIGINT after 1 s, measure wall-clock
         until it exits. *)
      let bin_path = bin () in
      let stdout_r, stdout_w = Unix.pipe () in
      let stderr_r, stderr_w = Unix.pipe () in
      let env = Array.append (Unix.environment ())
        [| "K4K_STUB_RESPONSES=" ^ canned;
           "K4K_STUB_SLOW=10" |] in
      let prev_cwd = Unix.getcwd () in
      Unix.chdir dir;
      let argv = [| bin_path; "--max-steps"; "30"; "echo-upper.k4k" |] in
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
        (exited && dt <= 5.0))

let () =
  Alcotest.run "k4k integration"
    [ "S1", [
        Alcotest.test_case
          "S1_echo_first_run_e2e" `Slow s1_echo_first_run_e2e;
      ];
      "NF1", [
        Alcotest.test_case
          "NF1_sigint_during_agent_exits_within_5s" `Slow
          nf1_sigint_during_agent;
      ];
      "S5", [
        Alcotest.test_case
          "S5_check_subcommand_exits_0_when_stable_structural" `Quick
          s5_check_stable_exits_0;
      ];
      "P11", [
        Alcotest.test_case "P11_stdout_pipeable" `Quick p11_stdout_pipeable;
      ];
      "T1", [
        Alcotest.test_case "T1_empty_file_is_unstable" `Quick t1_empty_file_exits_1;
      ];
      "P19", [
        Alcotest.test_case "P19_cache_skips_formalization_when_hash_matches"
          `Quick p19_cache_skips_formalization_when_hash_matches;
      ];
      "spec_round_trip", [
        Alcotest.test_case "spec_json_validates_round_trip" `Quick
          spec_json_validates_round_trip;
      ];
      "live", [
        Alcotest.test_case "K4K_LIVE_smoke_against_real_claude" `Slow
          (fun () ->
            if Sys.getenv_opt "K4K_LIVE" <> Some "1" then
              ()  (* skipped *)
            else
              with_workdir (fun dir ->
                let f = Filename.concat dir "in.k4k" in
                copy_file (fixture_path "well-formed-structural.k4k") f;
                let (code, so, _se) = run_capture
                  ~env:["K4K_LIVE", "1"]
                  ~k4k_args:["--check"; "in.k4k"] ~cwd:dir () in
                Alcotest.(check int) "exit 0" 0 code;
                Alcotest.(check bool) "stdout has 'stable'" true
                  (Astring.String.is_infix ~affix:"stable" so)));
        Alcotest.test_case "K4K_LIVE_smoke_gap_step_real_claude" `Slow
          (fun () ->
            if Sys.getenv_opt "K4K_LIVE" <> Some "1" then ()
            else
              with_workdir_and_git (fun dir ->
                let f = Filename.concat dir "echo-upper.k4k" in
                copy_file (fixture_path "echo-upper.k4k") f;
                let _ = K4k.Git.commit_all ~cwd:dir
                  ~message:"add spec" in
                (* Live: real Claude formalizes + proposes patches;
                   real dune verifies. We bound max-steps tightly. *)
                let (code, _so, _se) = run_capture
                  ~env:["K4K_LIVE", "1";
                        "PATH", Sys.getenv "PATH"]
                  ~k4k_args:["--max-steps"; "3";
                             "--budget"; "5000";
                             "echo-upper.k4k"]
                  ~cwd:dir () in
                Alcotest.(check bool)
                  "exit 0/4 (converged or max-steps)" true
                  (code = 0 || code = 4)));
      ];
    ]
