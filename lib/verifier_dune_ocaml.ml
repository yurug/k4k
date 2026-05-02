(** [Verifier_dune_ocaml] — v0 verifier adapter.

    Runs [dune build @runtest --force --display=quiet --root <workdir>],
    parses alcotest output (lib/Dune_output), and emits a
    [Verifier.run_result]. Persists stdout/stderr/result.json under
    [.k4k/verifier-runs/<id>/] when [k4k_dir] is provided. *)

type config = {
  dune_binary : string;
  timeout_s   : int;
  k4k_dir     : string option;     (* if Some, persist verifier-runs *)
  logger      : Logger.t option;   (* optional warnings sink for T20 *)
}

type t = {
  cfg : config;
  warnings : (string * string) list ref;
}

let name = "dune-ocaml"
let version _t = "0.1.0"

let default_config = {
  dune_binary = "dune";
  timeout_s   = 60;
  k4k_dir     = None;
  logger      = None;
}

let create cfg = { cfg; warnings = ref [] }

let warnings t = List.rev !(t.warnings)

let dune_args =
  ["build"; "@runtest"; "--force"; "--display=quiet"]

let map_kind : Dune_output.test_kind -> Verifier.status = function
  | `Ok -> `Established
  | `Fail -> `Contradicted

let collect_warnings (lines : Dune_output.test_line list) =
  List.filter_map (fun (l : Dune_output.test_line) ->
    if l.property_id = None
    then Some (l.test_name, "test name does not match P<id>_<slug>")
    else None) lines

let merge_status acc (pid, st) =
  match List.assoc_opt pid acc with
  | None -> (pid, st) :: acc
  | Some prev ->
      let chosen = match prev, st with
        | `Contradicted, _ | _, `Contradicted -> `Contradicted
        | _ -> st
      in
      (pid, chosen) :: List.remove_assoc pid acc

let dedup_by_property (lines : Dune_output.test_line list) =
  let recognized =
    List.filter_map (fun (l : Dune_output.test_line) ->
      match l.property_id with
      | Some pid -> Some (pid, map_kind l.kind)
      | None -> None) lines
  in
  List.fold_left merge_status [] recognized

let by_property_of_lines (lines : Dune_output.test_line list) ~focus
    : (string * Verifier.status) list * (string * string) list =
  let warns = collect_warnings lines in
  let dedup = dedup_by_property lines in
  let result =
    if focus = [] then dedup
    else
      List.map (fun pid ->
        match List.assoc_opt pid dedup with
        | Some s -> (pid, s)
        | None -> (pid, `Unknown)) focus
  in
  result, warns

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

let persist_run t ~run_id ~stdout ~stderr ~result =
  match t.cfg.k4k_dir with
  | None -> "", ""
  | Some k ->
      Persist.write_verifier_run ~k4k_dir:k ~run_id ~stdout ~stderr
        ~result;
      let dir = Filename.concat k
        (Filename.concat "verifier-runs" run_id) in
      Filename.concat dir "stdout.log",
      Filename.concat dir "stderr.log"

let emit_warnings t warns =
  List.iter (fun (n, _r) -> t.warnings := (n, _r) :: !(t.warnings)) warns;
  match t.cfg.logger with
  | None -> ()
  | Some lg ->
      List.iter (fun (n, r) ->
        Logger.warn lg "verifier.warning"
          (`Assoc [ "test_name", `String n; "reason", `String r ])
      ) warns

let make_ok t ~run_id ~exit_code ~duration_ms ~stdout ~stderr ~focus
    ~lines : Verifier.run_result =
  let by_property, warns = by_property_of_lines lines ~focus in
  emit_warnings t warns;
  let result_ok : Verifier.result_ok = {
    by_property;
    raw_exit_code = exit_code;
    stdout_path = "";
    stderr_path = "";
    duration_ms;
  } in
  let json = result_json_of result_ok in
  let so_p, se_p = persist_run t ~run_id ~stdout ~stderr ~result:json in
  `Ok { result_ok with stdout_path = so_p; stderr_path = se_p }

let interpret t ~run_id ~focus (sub : Subprocess.result)
    : Verifier.run_result =
  if sub.timed_out then
    `Tool_error (Printf.sprintf "dune timed out after %d s"
                   t.cfg.timeout_s)
  else if sub.exit_code = 130 then
    `Tool_error "dune interrupted (SIGINT)"
  else if sub.exit_code >= 2 then
    `Tool_error (Printf.sprintf "dune exited %d: %s" sub.exit_code
                   (String.trim sub.stderr))
  else
    (* Dune prints test output to stderr (not stdout). Concatenate
       both so the parser works regardless of which stream alcotest
       output ends up on (varies by dune version). *)
    let combined = sub.stdout ^ "\n" ^ sub.stderr in
    let lines = Dune_output.parse combined in
    if sub.exit_code = 1 && lines = [] then
      `Tool_error
        (Printf.sprintf "dune build error: %s"
           (String.trim sub.stderr))
    else
      make_ok t ~run_id ~exit_code:sub.exit_code
        ~duration_ms:sub.duration_ms ~stdout:sub.stdout
        ~stderr:sub.stderr ~focus ~lines

let run t ~workdir ~focus =
  let run_id = Persist.agent_run_id () in
  let args = dune_args @ ["--root"; workdir] in
  match Subprocess.run ~prog:t.cfg.dune_binary ~args
          ~timeout_s:t.cfg.timeout_s () with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
      `Tool_error "dune binary not found on PATH"
  | sub ->
      interpret t ~run_id ~focus sub
