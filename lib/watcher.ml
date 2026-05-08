(** [Watcher] — see [.mli]. Orchestrates startup + main loop.
    Implementation kept under the 200-line cap; loop body in
    [Watcher_loop]. *)

type config = {
  file_path        : string;
  k4k_dir          : string;
  verbosity        : [ `Quiet | `Verbose | `Debug ];
  exit_on_stable   : bool;
  poll_interval_ms : int;
}

type startup_outcome =
  | Started
  | Already_running of int
  | Aborted of string

let stem path =
  let b = Filename.basename path in
  try Filename.chop_extension b with Invalid_argument _ -> b

let ensure_starter_file ~file_path =
  if not (Sys.file_exists file_path) then begin
    let bytes = Starter_template.render ~name:(stem file_path) in
    Persist.atomic_write ~path:file_path bytes
  end

let ensure_frontmatter ~file_path =
  if Sys.file_exists file_path then begin
    let bytes = Persist.read_file file_path in
    let fixed = Starter_template.auto_frontmatter bytes in
    if fixed <> bytes then
      Persist.atomic_write ~path:file_path fixed
  end

(* ADR-013 §1: ensure the project is a git work tree. We do not call
   git directly here (the wrapper module does), but we use Git.is_repo
   / Git.init from lib/Git. *)
let ensure_git_repo ~cwd =
  if not (Git.is_repo ~cwd) then
    match Git.init ~cwd with
    | Ok () ->
        Git.configure_test_identity ~cwd;
        ()
    | Error msg ->
        raise (Error.K4k_error (Error.E_state_corrupt
          ("git init failed: " ^ msg)))

(* ADR-012 §4-§5: ensure cotype + git are on $PATH. We tolerate the
   stub-table being active in tests; in production we attempt a
   user-scoped install. Failure is fatal at startup. *)
let ensure_toolchain ~binary =
  match Toolchain_install.ensure ~binary with
  | Already_present _ | Installed _ -> ()
  | Needs_user_consent { reason; _ } ->
      raise (Error.K4k_error (Error.E_agent_unavailable
        (Printf.sprintf "%s needs user consent: %s" binary reason)))
  | Failed msg ->
      raise (Error.K4k_error (Error.E_agent_unavailable
        (Printf.sprintf "%s install failed: %s" binary msg)))

let resolve_abs path =
  if Filename.is_relative path then
    Filename.concat (Sys.getcwd ()) path
  else path

let startup ~config : startup_outcome =
  try
    let file = resolve_abs config.file_path in
    ensure_starter_file ~file_path:file;
    ensure_frontmatter ~file_path:file;
    let project_dir = Filename.dirname file in
    ensure_git_repo ~cwd:project_dir;
    (* Toolchain checks: cotype is required for v2 (ADR-010); git is
       required for ADR-013. *)
    ensure_toolchain ~binary:"cotype";
    ensure_toolchain ~binary:"git";
    match Watcher_pid.acquire ~k4k_dir:config.k4k_dir with
    | Error pid -> Already_running pid
    | Ok () -> Started
  with
  | Error.K4k_error e -> Aborted (Error.render e)
  | exn -> Aborted (Printexc.to_string exn)

let emit_event ~verbosity event details =
  let json = `Assoc [
    "ts", `String (Inline_blocks.timestamp_now ());
    "event", `String event;
    "details", details;
  ] in
  print_endline (Yojson.Safe.to_string json);
  match verbosity with
  | `Quiet -> ()
  | `Verbose | `Debug ->
      output_string stderr
        (Printf.sprintf "[k4k] %s\n" event);
      flush stderr

let run ~config : int =
  Sigint.install ();
  match startup ~config with
  | Already_running pid ->
      output_string stderr
        (Printf.sprintf "k4k: another watcher is running (pid %d)\n" pid);
      flush stderr; 5
  | Aborted msg ->
      output_string stderr (Printf.sprintf "k4k: %s\n" msg);
      flush stderr; 1
  | Started ->
      Sigint.register_cleanup
        (fun () -> Watcher_pid.release ~k4k_dir:config.k4k_dir);
      let cfg = {
        Watcher_loop.file_path = resolve_abs config.file_path;
        k4k_dir = config.k4k_dir;
        verbosity = config.verbosity;
        exit_on_stable = config.exit_on_stable;
        poll_interval_ms = config.poll_interval_ms;
        emit = (fun e d -> emit_event ~verbosity:config.verbosity e d);
      } in
      let rc = Watcher_loop.run cfg in
      Watcher_pid.release ~k4k_dir:config.k4k_dir;
      rc
