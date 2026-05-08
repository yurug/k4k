(** [Main] — v2 entry point. Single user-visible CLI form
    [k4k <file>]; the rest of the user UX is in-file via cotype.

    Operator flags:
    - [-v]   verbose stderr (engine-level transitions)
    - [-vv]  debug stderr (verbose + subprocess argv)
    - [--exit-on-stable] [@test_only] return after the first stability
            snapshot so integration tests don't have to send SIGTERM
    - [--help] / [--version] standard

    Exit codes: see [kb/spec/error-taxonomy.md] (startup-phase only —
    runtime issues surface in-file as [## k4k:status],
    [## k4k:clarification:*], [## k4k:tradeoff:proposal:*] blocks). *)

open K4k

let file_arg =
  let open Cmdliner in
  let doc = "Path to the .k4k interaction file." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"FILE" ~doc)

let verbosity_arg =
  let open Cmdliner in
  let v = Arg.(value & flag_all &
               info [ "v" ] ~doc:"Verbose stderr (operator); -vv for debug.") in
  let combine vs =
    let n = List.length vs in
    if n >= 2 then `Debug
    else if n = 1 then `Verbose
    else `Quiet
  in
  Term.(const combine $ v)
let exit_on_stable_arg =
  let open Cmdliner in
  Arg.(value & flag &
       info [ "exit-on-stable" ]
         ~doc:"Test-only: exit after the first stability snapshot. \
               Documented in kb/runbooks/test-environment.md.")

let dispatch verbosity exit_on_stable file =
  let cfg = {
    Watcher.file_path = file;
    k4k_dir = ".k4k";
    verbosity;
    exit_on_stable;
    poll_interval_ms = 500;
  } in
  Watcher.run ~config:cfg

let main_term =
  Cmdliner.Term.(const dispatch
                 $ verbosity_arg
                 $ exit_on_stable_arg
                 $ file_arg)

let cmd =
  let info = Cmdliner.Cmd.info "k4k"
    ~version:"0.2.0"
    ~doc:"k4k — autonomous coding-agent watcher (ADR-011)."
  in
  Cmdliner.Cmd.v info main_term

let () = exit (Cmdliner.Cmd.eval' cmd)
