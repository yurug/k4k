(** [Main] — CLI entry point for [k4k].

    Step 2 supports [k4k --check <file.k4k>] which runs structural +
    semantic stability and persists [.k4k/characterization/desired/].
    The full convergence loop (no [--check]) lands in step 3.

    Verifier is selected per ADR-008: default [Verifier_external] (the
    generic adapter), or [Verifier_stub] when [K4K_STUB_RESPONSES] is
    set (test-only path). The verifier executable + timeout come from
    the interaction file's [k4k.verifier] frontmatter, optionally
    overridden by [--verifier]/[--verifier-timeout]. *)

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

let status_flag_arg =
  let open Cmdliner in
  Arg.(value & flag &
       info [ "status" ]
         ~doc:"Print the current gap from .k4k/. \
               No agent or verifier calls.")

let reset_flag_arg =
  let open Cmdliner in
  Arg.(value & flag &
       info [ "reset" ]
         ~doc:"Wipe .k4k/ for this project. Requires --yes.")

let yes_flag_arg =
  let open Cmdliner in
  Arg.(value & flag &
       info [ "yes" ]
         ~doc:"Skip the --reset confirmation prompt.")

let no_color_flag_arg =
  let open Cmdliner in
  Arg.(value & flag &
       info [ "no-color" ]
         ~doc:"Disable ANSI colour / cursor escapes in stdout.")

let max_steps_arg =
  let open Cmdliner in
  Arg.(value & opt int 50 &
       info [ "max-steps" ] ~docv:"N"
         ~doc:"Maximum gap-step iterations (default 50).")

let budget_arg =
  let open Cmdliner in
  Arg.(value & opt int 1000 &
       info [ "budget" ] ~docv:"M"
         ~doc:"Hard budget cap (default 1000 units).")

let verifier_cmd_arg =
  let open Cmdliner in
  Arg.(value & opt (some string) None &
       info [ "verifier" ] ~docv:"CMD"
         ~doc:"Override the verifier command (whitespace-separated).")

let verifier_timeout_arg =
  let open Cmdliner in
  Arg.(value & opt (some int) None &
       info [ "verifier-timeout" ] ~docv:"S"
         ~doc:"Override the verifier timeout in seconds.")

let live_backend () =
  Sys.getenv_opt "K4K_LIVE" = Some "1"

(* For test environments: a JSON file at $K4K_STUB_RESPONSES.
   Round-robin per purpose. *)
let load_stub_canned_from_env () =
  match Sys.getenv_opt "K4K_STUB_RESPONSES" with
  | None | Some "" -> []
  | Some path ->
      let raw = Persist.read_file path in
      (match Yojson.Safe.from_string raw with
       | `List entries ->
           let f_count = ref 0 in
           let g_count = ref 0 in
           let mk_entry idx_in_purpose e =
             let fs = match e with `Assoc xs -> xs | _ -> [] in
             let text = match List.assoc_opt "text" fs with
               | Some (`String s) -> s | _ -> "" in
             let purpose = match List.assoc_opt "purpose" fs with
               | Some (`String "Gap_step") -> `Gap_step
               | Some (`String "Kb_regen") -> `Kb_regen
               | _ -> `Formalization in
             let match_sub = match List.assoc_opt "match" fs with
               | Some (`String s) -> Some s | _ -> None in
             let counter = match purpose with
               | `Gap_step -> g_count
               | _ -> f_count in
             let trigger prompt =
               match match_sub with
               | Some s -> Astring.String.is_infix ~affix:s prompt
               | None ->
                   if !counter = idx_in_purpose then begin
                     incr counter; true
                   end else false
             in
             { Backend_stub.purpose; trigger; payload = Ok text }
           in
           let ix = Hashtbl.create 4 in
           List.map (fun e ->
             let purpose_str = match e with
               | `Assoc fs ->
                   (match List.assoc_opt "purpose" fs with
                    | Some (`String s) -> s
                    | _ -> "Formalization")
               | _ -> "Formalization"
             in
             let cur = try Hashtbl.find ix purpose_str with Not_found -> 0 in
             Hashtbl.replace ix purpose_str (cur + 1);
             mk_entry cur e) entries
       | _ -> [])

let make_backend () =
  if live_backend () then
    `Claude (Backend_claude.create Backend_claude.default_config)
  else
    let canned = load_stub_canned_from_env () in
    `Stub (Backend_stub.create
             { Backend_stub.default_config with responses = canned })

let run_check verbosity file =
  Sigint.install ();
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
            ~backend:b ~inputs ()
      | `Stub b ->
          Full_check.run
            (module Backend_stub) (module Verifier_stub)
            ~backend:b ~inputs ()
    in
    Logger.stdout_line logger "stable"; 0
  with
  | Error.K4k_error err ->
      Logger.error logger err; Error.exit_code_of err
  | Error.Invariant_violation msg ->
      output_string stderr (Printf.sprintf "k4k: BUG: %s\n" msg);
      flush stderr; 64

(* Read the verifier config from frontmatter; merge in CLI overrides. *)
let read_verifier_config ~file ~cli_cmd ~cli_timeout =
  let parsed =
    try
      let content = Persist.read_file file in
      Some (Parser.parse content)
    with _ -> None
  in
  let fm_cmd, fm_to = match parsed with
    | None -> None, None
    | Some p ->
        p.Parser.frontmatter.verifier_command,
        p.Parser.frontmatter.verifier_timeout_s
  in
  let cmd = match cli_cmd with
    | Some s ->
        Some (List.filter (fun x -> x <> "")
                (String.split_on_char ' ' s))
    | None -> fm_cmd
  in
  let timeout = match cli_timeout with
    | Some n when n > 0 -> n
    | _ ->
        (match fm_to with
         | Some n when n > 0 -> n
         | _ -> 60)
  in
  cmd, timeout

let raise_unstable_missing_verifier () =
  raise (Error.K4k_error
           (Error.E_unstable
              [ Error.issue ~section:"frontmatter"
                  "k4k.verifier.command is required (set in frontmatter \
                   or pass --verifier)" ]))

let make_external_verifier ~k4k_dir ~logger ~command ~timeout_s =
  Verifier_external.create
    { Verifier_external.command;
      timeout_s;
      k4k_dir = Some k4k_dir;
      logger = Some logger; }

let run_with_external verbosity file ~max_steps ~budget
    ~command ~timeout_s =
  let k4k_dir = ".k4k" in
  let jsonl_path = Some (Filename.concat k4k_dir "log.jsonl") in
  let logger = Logger.create ~verbosity ~jsonl_path in
  let inputs = Harness.{ file_path = file; k4k_dir; logger } in
  let cfg = { Run_loop.max_steps; budget; between_steps = None } in
  let verifier = make_external_verifier ~k4k_dir ~logger
                   ~command ~timeout_s in
  let _outcome =
    match make_backend () with
    | `Claude b ->
        Convergence.run
          (module Backend_claude) (module Verifier_external)
          ~backend:b ~verifier ~inputs ~cfg
    | `Stub b ->
        Convergence.run
          (module Backend_stub) (module Verifier_external)
          ~backend:b ~verifier ~inputs ~cfg
  in
  let _ = _outcome in
  Logger.stdout_line logger "done"; 0

let run_convergence verbosity file ~max_steps ~budget
    ~cli_verifier ~cli_verifier_timeout =
  Sigint.install ();
  try
    let cmd, timeout = read_verifier_config ~file
                        ~cli_cmd:cli_verifier
                        ~cli_timeout:cli_verifier_timeout in
    match cmd with
    | None | Some [] -> raise_unstable_missing_verifier ()
    | Some command ->
        run_with_external verbosity file ~max_steps ~budget
          ~command ~timeout_s:timeout
  with
  | Error.K4k_error err ->
      let logger = Logger.create ~verbosity
        ~jsonl_path:(Some ".k4k/log.jsonl") in
      Logger.error logger err; Error.exit_code_of err
  | Error.Invariant_violation msg ->
      output_string stderr (Printf.sprintf "k4k: BUG: %s\n" msg);
      flush stderr; 64

(* C2 — --status. Read .k4k/gap/properties.json and print one line
   per property: "<id>  <status>  risk=<score>". No agent or verifier
   calls. Exit 0 always (or 5 if .k4k/ is missing). *)
let render_status_line (p : K4k.Property.t) =
  let st = K4k.Property_json.status_to_string p.status in
  Printf.sprintf "%s  %s  risk=%.4f" p.id st p.risk_score

let run_status _verbosity _file =
  let k4k_dir = ".k4k" in
  let dir_present =
    Sys.file_exists k4k_dir
    && (try Sys.is_directory k4k_dir with Sys_error _ -> false) in
  if not dir_present then begin
    output_string stderr "k4k: state corrupt: .k4k/ not present; \
                          run k4k <file.k4k> first\n";
    flush stderr; 5
  end else
    match K4k.Persist.read_gap ~k4k_dir with
    | None ->
        output_string stdout "(no gap recorded; nothing to report)\n";
        flush stdout; 0
    | Some bytes ->
        let parsed =
          try Some (Yojson.Safe.from_string bytes) with _ -> None
        in
        (match parsed with
         | None | Some (`Null) ->
             output_string stdout "(empty gap)\n"; flush stdout; 0
         | Some j ->
             let ps = K4k.Property_json.list_of_yojson j in
             List.iter (fun p ->
               output_string stdout (render_status_line p ^ "\n"))
               ps;
             flush stdout; 0)

(* C2 — --reset. Walk .k4k/ recursively and delete it. Requires
   --yes; otherwise refuse and print a remediation hint. Exit 0
   on success; .k4k/ missing is also success. *)
let rec rm_rf path =
  match Unix.lstat path with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
  | st when st.st_kind = Unix.S_DIR ->
      let entries = Sys.readdir path in
      Array.iter (fun e ->
        rm_rf (Filename.concat path e)) entries;
      (try Unix.rmdir path with _ -> ())
  | _ ->
      (try Unix.unlink path with _ -> ())

let run_reset ~yes _verbosity _file =
  if not yes then begin
    output_string stderr
      "k4k: --reset requires --yes (this wipes .k4k/ for this \
       project); re-run with --reset --yes\n";
    flush stderr; 1
  end else begin
    rm_rf ".k4k";
    0
  end

let dispatch verbosity check_flag status_flag reset_flag yes_flag
    no_color_flag max_steps budget
    cli_verifier cli_verifier_timeout file =
  if no_color_flag then K4k.Logger.Tty_status.set_color_enabled false;
  if status_flag then run_status verbosity file
  else if reset_flag then run_reset ~yes:yes_flag verbosity file
  else if check_flag then run_check verbosity file
  else run_convergence verbosity file ~max_steps ~budget
         ~cli_verifier ~cli_verifier_timeout

let _ = H.check  (* keep step-1 surface alive *)

let check_term =
  Cmdliner.Term.(const dispatch
                 $ verbosity_arg $ check_flag_arg
                 $ status_flag_arg $ reset_flag_arg $ yes_flag_arg
                 $ no_color_flag_arg
                 $ max_steps_arg $ budget_arg
                 $ verifier_cmd_arg $ verifier_timeout_arg
                 $ file_arg)

let cmd =
  let info = Cmdliner.Cmd.info "k4k"
    ~version:"0.2.0"
    ~doc:"k4k — KISS for KISS, deterministic harness."
  in
  Cmdliner.Cmd.v info check_term

let () = exit (Cmdliner.Cmd.eval' cmd)
