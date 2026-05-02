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

let run_capture ~k4k_args ~cwd =
  let bin_path = bin () in
  let prev = Sys.getcwd () in
  Sys.chdir cwd;
  let cmd = Printf.sprintf
    "%s %s 1>%s 2>%s"
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
    let (code, so, se) = run_capture
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir in
    Alcotest.(check int) "exit 0" 0 code;
    Alcotest.(check string) "stdout exact"
      "stable (structural-only)\n" so;
    Alcotest.(check string) "stderr empty (default verbosity)" "" se;
    Alcotest.(check bool) "manifest written" true
      (Sys.file_exists (Filename.concat dir ".k4k/manifest.json"));
    Alcotest.(check bool) "log written" true
      (Sys.file_exists (Filename.concat dir ".k4k/log.jsonl")))

let p11_stdout_pipeable () =
  with_workdir (fun dir ->
    let f = Filename.concat dir "in.k4k" in
    copy_file (fixture_path "well-formed-structural.k4k") f;
    let (_, so, _) = run_capture
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir in
    (* P11: a single line, exactly the documented protocol output. *)
    let lines = String.split_on_char '\n' so in
    let non_empty = List.filter (fun s -> s <> "") lines in
    Alcotest.(check int) "exactly one stdout line"
      1 (List.length non_empty);
    Alcotest.(check string) "stdout payload"
      "stable (structural-only)" (List.hd non_empty))

let t1_empty_file_exits_1 () =
  with_workdir (fun dir ->
    let f = Filename.concat dir "in.k4k" in
    let oc = open_out f in close_out oc;
    let (code, _, se) = run_capture
      ~k4k_args:["--check"; "in.k4k"] ~cwd:dir in
    Alcotest.(check int) "exit 1" 1 code;
    Alcotest.(check bool) "stderr mentions unstable" true
      (Astring.String.is_infix ~affix:"unstable" se))

let () =
  Alcotest.run "k4k integration"
    [ "S5", [
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
    ]
