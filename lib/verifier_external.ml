(** [Verifier_external] — the only production verifier adapter.

    Spawns a configured external executable per
    [kb/external/verifier-protocol.md] and parses the JSON result file
    it writes. k4k carries no verifier-specific knowledge: tool-output
    regexes / exit-code maps live inside the verifier executable,
    not here. *)

type config = {
  command   : string list;        (* >= 1 element; first is prog *)
  timeout_s : int;                (* wall-clock cap; default 60 *)
  k4k_dir   : string option;      (* if Some, persist verifier-runs *)
  logger    : Logger.t option;    (* sink for verifier.warning events *)
}

type t = { cfg : config }

let name = "external"

(* H6 — version reflects the configured command's basename, not a
   hardcoded "0.1.0-stub". *)
let version t = match t.cfg.command with
  | [] -> "external/(unconfigured)"
  | prog :: _ -> "external/" ^ Filename.basename prog

let default_config = {
  command   = [];      (* must be set explicitly; empty is invalid *)
  timeout_s = 60;
  k4k_dir   = None;
  logger    = None;
}

let create cfg = { cfg }

let truncate_stderr s =
  let n = String.length s in
  if n <= 200 then s
  else String.sub s 0 200

let result_json_of (r : Verifier.result_ok) : string =
  let by =
    List.map (fun (pid, st) ->
      let s = match st with
        | `Established -> "established"
        | `Contradicted -> "contradicted"
        | `Unknown -> "unknown"
      in
      (pid, `String s)) r.by_property
  in
  let j : Yojson.Safe.t = `Assoc [
    "by_property", `Assoc by;
    "raw_exit_code", `Int r.raw_exit_code;
    "duration_ms", `Int r.duration_ms;
  ] in
  Canonical_json.to_string j

let persist_run cfg ~run_id ~stdout ~stderr ~result =
  match cfg.k4k_dir with
  | None -> "", ""
  | Some k ->
      Persist.write_verifier_run ~k4k_dir:k ~run_id ~stdout ~stderr
        ~result;
      let dir = Filename.concat k
        (Filename.concat "verifier-runs" run_id) in
      Filename.concat dir "stdout.log",
      Filename.concat dir "stderr.log"

let emit_warnings cfg (warns : Verifier_external_parse.warning list) =
  match cfg.logger with
  | None -> ()
  | Some lg ->
      List.iter (fun (w : Verifier_external_parse.warning) ->
        Logger.warn lg "verifier.warning"
          (`Assoc [ "kind", `String w.kind;
                    "message", `String w.message ])
      ) warns

let read_output_or_error path =
  if not (Sys.file_exists path) then
    Error ("verifier wrote no output file at " ^ path)
  else
    try
      let content = Persist.read_file path in
      (* Pre-touched empty (NF4); treat empty as "no output". *)
      if content = "" then
        Error ("verifier wrote no output file at " ^ path)
      else Ok content
    with _ -> Error ("could not read verifier output at " ^ path)

(* C1 — NF4 envelope: verifier output under <k4k_dir>/scratch/<id>/,
   never /tmp. Pre-touched so K4K_TEST_TRACE_WRITES sees the path. *)
let make_output_path ~k4k_dir ~run_id =
  let base = match k4k_dir with
    | Some d -> Filename.concat d "scratch"
    | None -> Filename.concat ".k4k" "scratch"
  in
  let dir = Filename.concat base run_id in
  Persist.ensure_dir dir;
  let path = Filename.concat dir "verifier-output.json" in
  Persist.atomic_write ~path "";
  path

let cleanup_output path =
  try Sys.remove path with Sys_error _ -> ()

let interpret_ok t ~run_id ~focus ~sub
    (parsed : Verifier_external_parse.parsed)
    : Verifier.run_result =
  emit_warnings t.cfg parsed.warnings;
  let by =
    Verifier_external_parse.with_focus_padding
      ~focus parsed.by_property in
  let result_ok : Verifier.result_ok = {
    by_property   = by;
    raw_exit_code = parsed.raw_exit_code;
    stdout_path   = "";
    stderr_path   = "";
    duration_ms   = parsed.duration_ms;
  } in
  let json = result_json_of result_ok in
  let so_p, se_p = persist_run t.cfg ~run_id
                     ~stdout:sub.Subprocess.stdout
                     ~stderr:sub.Subprocess.stderr ~result:json in
  `Ok { result_ok with stdout_path = so_p; stderr_path = se_p }

let nonzero_exit_msg ~exit_code ~stderr =
  Printf.sprintf "verifier exited %d: %s" exit_code
    (truncate_stderr (String.trim stderr))

let interpret t ~run_id ~focus ~output_path
    (sub : Subprocess.result) : Verifier.run_result =
  if sub.timed_out then
    `Tool_error (Printf.sprintf "verifier timed out after %d s"
                   t.cfg.timeout_s)
  else if sub.exit_code = 130 then
    `Tool_error "verifier interrupted (SIGINT)"
  else if sub.exit_code <> 0 then
    `Tool_error (nonzero_exit_msg ~exit_code:sub.exit_code
                   ~stderr:sub.stderr)
  else
    match read_output_or_error output_path with
    | Error msg -> `Tool_error msg
    | Ok raw ->
        match Verifier_external_parse.parse raw with
        | Error e ->
            `Tool_error (Verifier_external_parse.render_error e)
        | Ok parsed ->
            interpret_ok t ~run_id ~focus ~sub parsed

let raise_invalid_config () =
  raise (Error.K4k_error
           (Error.E_verifier_unavailable
              "verifier command is empty (set k4k.verifier.command)"))

let split_command cfg =
  match cfg.command with
  | [] -> raise_invalid_config ()
  | prog :: rest -> prog, rest

let debug_argv t ~prog ~args =
  match t.cfg.logger with
  | None -> ()
  | Some lg ->
      let argv_json : Yojson.Safe.t =
        `List (List.map (fun s -> `String s) (prog :: args)) in
      Logger.debug lg "verifier.argv"
        (`Assoc [ "argv", argv_json ])

let run t ~workdir ~focus =
  let prog, rest = split_command t.cfg in
  let run_id = Persist.agent_run_id () in
  let output = make_output_path ~k4k_dir:t.cfg.k4k_dir ~run_id in
  let args = rest @ ["--workdir"; workdir]
             @ (if focus = [] then [] else "--focus" :: focus)
             @ ["--output"; output] in
  debug_argv t ~prog ~args;
  let res =
    match Subprocess.run ~prog ~args ~timeout_s:t.cfg.timeout_s () with
    | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
        `Missing
    | sub -> `Sub sub
  in
  let r = match res with
    | `Missing ->
        `Tool_error (Printf.sprintf
          "verifier binary not found: %s" prog)
    | `Sub sub ->
        interpret t ~run_id ~focus ~output_path:output sub
  in
  cleanup_output output;
  r
