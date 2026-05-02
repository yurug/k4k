(** [Main] — CLI entry point for [k4k].

    Step 2 supports [k4k --check <file.k4k>] which runs structural +
    semantic stability and persists [.k4k/characterization/desired/].
    The full convergence loop (no [--check]) lands in step 3. *)

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
       info [ "check" ] ~doc:"Run only the stability check.")

let live_backend () =
  Sys.getenv_opt "K4K_LIVE" = Some "1"

(* For test environments: a JSON file at $K4K_STUB_RESPONSES whose
   contents mirror [Backend_stub.config.responses] but with [trigger] as
   a "match-any" predicate. Each entry: {"purpose": "Formalization",
   "text": "..."}. The runtime turns these into round-robin canned
   responses. *)
let load_stub_canned_from_env () =
  match Sys.getenv_opt "K4K_STUB_RESPONSES" with
  | None | Some "" -> []
  | Some path ->
      let raw = Persist.read_file path in
      (match Yojson.Safe.from_string raw with
       | `List entries ->
           let counter = ref 0 in
           List.mapi (fun i e ->
             let fs = match e with `Assoc xs -> xs | _ -> [] in
             let text = match List.assoc_opt "text" fs with
               | Some (`String s) -> s | _ -> "" in
             let purpose = match List.assoc_opt "purpose" fs with
               | Some (`String "Gap_step") -> `Gap_step
               | Some (`String "Kb_regen") -> `Kb_regen
               | _ -> `Formalization in
             { Backend_stub.purpose;
               trigger = (fun _ ->
                 let ok = !counter = i in
                 if ok then incr counter; ok);
               payload = Ok text })
             entries
       | _ -> [])

let make_backend () =
  if live_backend () then
    `Claude (Backend_claude.create Backend_claude.default_config)
  else
    let canned = load_stub_canned_from_env () in
    `Stub (Backend_stub.create
             { Backend_stub.default_config with responses = canned })

let run_check verbosity file =
  let k4k_dir = ".k4k" in
  let jsonl_path = Some (Filename.concat k4k_dir "log.jsonl") in
  let logger = Logger.create ~verbosity ~jsonl_path in
  let inputs = Harness.{ file_path = file; k4k_dir; logger } in
  try
    let _ : Characterization.t =
      match make_backend () with
      | `Claude b ->
          Full_check.run
            (module Backend_claude) (module Verifier_stub)
            ~backend:b ~inputs
      | `Stub b ->
          Full_check.run
            (module Backend_stub) (module Verifier_stub)
            ~backend:b ~inputs
    in
    Logger.stdout_line logger "stable"; 0
  with
  | Error.K4k_error err ->
      Logger.error logger err; Error.exit_code_of err
  | Error.Invariant_violation msg ->
      output_string stderr (Printf.sprintf "k4k: BUG: %s\n" msg);
      flush stderr; 64

let dispatch verbosity check_flag file =
  if not check_flag then begin
    output_string stderr "k4k: only --check is supported in step 2\n";
    flush stderr; 1
  end else
    run_check verbosity file

let _ = H.check  (* keep step-1 surface alive *)

let check_term =
  Cmdliner.Term.(const dispatch $ verbosity_arg $ check_flag_arg $ file_arg)

let cmd =
  let info = Cmdliner.Cmd.info "k4k"
    ~version:"0.2.0"
    ~doc:"k4k — KISS for KISS, deterministic harness."
  in
  Cmdliner.Cmd.v info check_term

let () = exit (Cmdliner.Cmd.eval' cmd)
