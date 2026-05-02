(** [Main] — CLI entry point for [k4k].

    Step 1 supports only one form: [k4k --check <file.k4k>]. The full
    convergence loop (no [--check]) lands in step 3. The dispatcher
    constructs the harness with [Backend_stub] + [Verifier_stub].
*)

open K4k

module H = Harness.Make (Backend_stub) (Verifier_stub)

let file_arg =
  let open Cmdliner in
  let doc = "Path to the .k4k interaction file." in
  Arg.(required & pos 0 (some file) None & info [] ~docv:"FILE" ~doc)

let verbosity_arg =
  let open Cmdliner in
  let v = Arg.(value & flag & info [ "v" ] ~doc:"Verbose stderr.") in
  let vv = Arg.(value & flag & info [ "vv" ] ~doc:"Debug stderr.") in
  let combine v vv =
    if vv then `Debug else if v then `Verbose else `Quiet
  in
  Term.(const combine $ v $ vv)

let check_flag_arg =
  let open Cmdliner in
  Arg.(value & flag &
       info [ "check" ] ~doc:"Run only the structural stability check.")

let run_check verbosity file =
  let k4k_dir = ".k4k" in
  let jsonl_path = Some (Filename.concat k4k_dir "log.jsonl") in
  let logger = Logger.create ~verbosity ~jsonl_path in
  let inputs = Harness.{ file_path = file; k4k_dir; logger } in
  try
    match H.check inputs with
    | Harness.Stable_structural ->
        Logger.stdout_line logger "stable (structural-only)"; 0
    | Harness.Unstable -> 1
  with
  | Error.K4k_error err ->
      Logger.error logger err; Error.exit_code_of err
  | Error.Invariant_violation msg ->
      output_string stderr (Printf.sprintf "k4k: BUG: %s\n" msg);
      flush stderr; 64

let dispatch verbosity check_flag file =
  if not check_flag then begin
    output_string stderr "k4k: only --check is supported in step 1\n";
    flush stderr; 1
  end else
    run_check verbosity file

let check_term =
  Cmdliner.Term.(const dispatch $ verbosity_arg $ check_flag_arg $ file_arg)

let cmd =
  let info = Cmdliner.Cmd.info "k4k"
    ~version:"0.1.0"
    ~doc:"k4k — KISS for KISS, deterministic harness."
  in
  Cmdliner.Cmd.v info check_term

let () = exit (Cmdliner.Cmd.eval' cmd)
