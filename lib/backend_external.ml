(** [Backend_external] — the only production agent-backend adapter.

    Spawns a configured external executable per
    [kb/external/backend-protocol.md] and parses the JSON result file
    it writes. k4k carries no backend-specific knowledge: tool-output
    parsing / API calls / retry quirks live inside the backend
    executable, not here. ADR-009. *)

type config = {
  command   : string list;        (* >= 1 element; first is prog *)
  timeout_s : int;                (* wall-clock cap; default 300 *)
  k4k_dir   : string option;      (* if Some, persist agent-runs *)
  logger    : Logger.t option;    (* sink for backend.* events *)
}

type t = { cfg : config }

let name = "external"

let version t = match t.cfg.command with
  | [] -> "external/(unconfigured)"
  | prog :: _ -> "external/" ^ Filename.basename prog

let default_config = {
  command   = []; timeout_s = 300; k4k_dir = None; logger = None;
}

let create cfg = { cfg }

let purpose_to_string = function
  | `Formalization -> "formalization"
  | `Gap_step      -> "gap-step"
  | `Kb_regen      -> "kb-regen"

(* C1 — NF4 envelope: prompt + output under <k4k_dir>/scratch/<id>/,
   never /tmp. Pre-touched so K4K_TEST_TRACE_WRITES sees the path. *)
let make_scratch_dir ~k4k_dir ~run_id =
  let base = match k4k_dir with
    | Some d -> Filename.concat d "scratch"
    | None -> Filename.concat (Filename.get_temp_dir_name ())
                "k4k-backend-scratch"
  in
  let dir = Filename.concat base run_id in
  Persist.ensure_dir dir;
  dir

let pre_touch path = Persist.atomic_write ~path ""

let cleanup_path path = try Sys.remove path with Sys_error _ -> ()

let split_command cfg =
  match cfg.command with
  | [] ->
      raise (Error.K4k_error
               (Error.E_agent_unavailable
                  "backend command is empty (set k4k.backend.command)"))
  | prog :: rest -> prog, rest

let debug_argv t ~prog ~args =
  match t.cfg.logger with
  | None -> ()
  | Some lg ->
      Logger.debug lg "backend.argv"
        (`Assoc [ "argv",
                  `List (List.map (fun s -> `String s) (prog :: args)) ])

let read_output_or_error path =
  if not (Sys.file_exists path) then
    Error ("backend wrote no output file at " ^ path)
  else
    try
      let content = Persist.read_file path in
      if content = "" then
        Error ("backend wrote no output file at " ^ path)
      else Ok content
    with _ -> Error ("could not read backend output at " ^ path)

let truncate_stderr s =
  let n = String.length s in
  if n <= 200 then s else String.sub s 0 200

let persist_run cfg ~run_id ~prompt ~response ~verdict =
  match cfg.k4k_dir with
  | None -> ()
  | Some k ->
      Persist.write_agent_run ~k4k_dir:k ~run_id
        ~prompt ~response ~verdict

let verdict_json (p : Backend_external_parse.parsed) : string =
  let oc_str = match p.outcome with
    | Ok_outcome -> "ok"
    | Budget_exhausted_outcome -> "budget_exhausted"
    | Tool_error_outcome -> "tool_error" in
  Canonical_json.to_string (`Assoc [
    "outcome", `String oc_str;
    "budget_used", `Int p.budget_used;
    "duration_ms", `Int p.duration_ms;
    "error", `String p.error; ])

let to_result (p : Backend_external_parse.parsed) : Agent_backend.result =
  match p.outcome with
  | Ok_outcome ->
      `Ok Agent_backend.{ text = p.text; budget_used = p.budget_used;
                          duration_ms = p.duration_ms }
  | Budget_exhausted_outcome -> `Budget_exhausted
  | Tool_error_outcome -> `Tool_error p.error

(* Spawn once. Returns [`Done r] for terminal results (no retry),
   [`Retry msg] for transient failures, [`Parsed parsed] when the
   result file parses cleanly (caller decides what to do). *)
let attempt_once t ~prog ~args ~budget ~output =
  let res =
    try `Sub (Subprocess.run ~prog ~args ~timeout_s:t.cfg.timeout_s ())
    with Unix.Unix_error (Unix.ENOENT, _, _) -> `Missing
  in
  match res with
  | `Missing ->
      `Done (`Tool_error (Printf.sprintf
        "backend binary not found: %s" prog))
  | `Sub sub when sub.timed_out ->
      `Done (`Tool_error (Printf.sprintf
        "backend timed out after %d s" t.cfg.timeout_s))
  | `Sub sub when sub.exit_code = 130 ->
      `Done (`Tool_error "backend interrupted")
  | `Sub sub when sub.exit_code <> 0 ->
      `Retry (Printf.sprintf "backend exited %d: %s" sub.exit_code
                (truncate_stderr (String.trim sub.stderr)))
  | `Sub _ ->
      match read_output_or_error output with
      | Error msg -> `Retry msg
      | Ok raw ->
          (match Backend_external_parse.parse ~budget raw with
           | Error e -> `Retry (Backend_external_parse.render_error e)
           | Ok parsed -> `Parsed parsed)

(* Backoff: 250ms, 500ms, 1000ms (doubling). *)
let backoff_seconds attempt =
  Float.of_int (250 lsl attempt) /. 1000.0

let max_retries = 3

let handle_parsed t ~run_id ~prompt (parsed : Backend_external_parse.parsed) =
  let res = to_result parsed in
  (match res with
   | `Ok _ | `Budget_exhausted ->
       persist_run t.cfg ~run_id ~prompt ~response:parsed.text
         ~verdict:(verdict_json parsed)
   | `Tool_error _ -> ());
  res

let make_args ~rest ~purpose ~prompt_path ~budget ~output =
  rest @ [
    "--purpose"; purpose_to_string purpose;
    "--prompt-file"; prompt_path;
    "--budget"; string_of_int budget;
    "--output"; output; ]

let rec retry_loop t ~run_id ~prompt ~prog ~args ~budget ~output n last_msg =
  if n >= max_retries then
    `Tool_error (Printf.sprintf "backend failed after %d attempts: %s"
                   max_retries last_msg)
  else
    match attempt_once t ~prog ~args ~budget ~output with
    | `Done r -> r
    | `Parsed parsed -> handle_parsed t ~run_id ~prompt parsed
    | `Retry msg ->
        if n + 1 < max_retries then begin
          Unix.sleepf (backoff_seconds n);
          cleanup_path output;
          pre_touch output;
          retry_loop t ~run_id ~prompt ~prog ~args ~budget ~output
            (n + 1) msg
        end else
          `Tool_error (Printf.sprintf
            "backend failed after %d attempts: %s"
            max_retries msg)

let invoke_with_run_id t ~purpose ~prompt ~budget ~run_id =
  let prog, rest = split_command t.cfg in
  let scratch_dir = make_scratch_dir ~k4k_dir:t.cfg.k4k_dir ~run_id in
  let prompt_path = Filename.concat scratch_dir "prompt.txt" in
  Persist.atomic_write ~path:prompt_path prompt;
  let output = Filename.concat scratch_dir "backend-output.json" in
  pre_touch output;
  let args = make_args ~rest ~purpose ~prompt_path ~budget ~output in
  debug_argv t ~prog ~args;
  let r = retry_loop t ~run_id ~prompt ~prog ~args ~budget ~output 0 "" in
  cleanup_path output;
  cleanup_path prompt_path;
  r

let invoke t ~purpose ~prompt ~budget =
  let run_id = Persist.agent_run_id () in
  invoke_with_run_id t ~purpose ~prompt ~budget ~run_id
