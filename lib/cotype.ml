(** [Cotype] — thin wrapper around the `cotype` CLI (PyPI).

    Per ADR-010, k4k delegates user-agent interaction-file concurrency
    to cotype. This module owns the contract surface: every shell-out
    to `cotype` happens here, and downstream callers (Persist,
    bin/main.ml) MUST go through this module.

    Load-bearing rule: callers read from the [base_path] returned by
    [open_], NEVER directly from FILE. *)

type config = { binary : string }

let default_config = { binary = "cotype" }

type t = { cfg : config; mutable cached_version : string option }

let create cfg = { cfg; cached_version = None }

let name = "cotype"

let raise_unavailable msg =
  raise (Error.K4k_error (Error.E_agent_unavailable msg))

let raise_state msg =
  raise (Error.K4k_error (Error.E_state_corrupt msg))

let install_hint =
  "cotype not on PATH; install with `pipx install cotype` (or `pip install cotype`)"

let run_cotype ?stdin t ~args =
  try Subprocess.run ?stdin ~prog:t.cfg.binary ~args ~timeout_s:60 ()
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> raise_unavailable install_hint
  | Unix.Unix_error (e, _, _) ->
      raise_unavailable
        (Printf.sprintf "cotype subprocess error: %s" (Unix.error_message e))

(* `cotype --version` → "cotype 0.2.3" on stdout (no JSON). *)
let version t =
  match t.cached_version with
  | Some v -> v
  | None ->
      let r = run_cotype t ~args:["--version"] in
      let raw = String.trim r.stdout in
      let v = match String.split_on_char ' ' raw with
        | _ :: v :: _ -> v
        | [v] -> v
        | [] -> raw
      in
      t.cached_version <- Some v; v

let init t ~file =
  let r = run_cotype t ~args:["init"; file; "--json"] in
  Cotype_parse.parse_init (Cotype_parse.json_or_raise r.stdout)

(* `cotype open` itself auto-initializes when the file is unmanaged
   (per the live-tested 0.2.3 behavior); init is idempotent. *)
let ensure_init = init

type open_result = Cotype_parse.open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

let open_ t ~file =
  let r = run_cotype t ~args:["open"; file; "--json"] in
  Cotype_parse.parse_open (Cotype_parse.json_or_raise r.stdout)

type save_outcome = Cotype_parse.save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

let save t ~file ~base_sha ~actor ~bytes =
  let args =
    ["save"; file; "--base-sha"; base_sha; "--actor"; actor; "--json"] in
  let r = run_cotype t ~args ~stdin:bytes in
  Cotype_parse.parse_save (Cotype_parse.json_or_raise r.stdout)

let status t ~file =
  let r = run_cotype t ~args:["status"; file; "--json"] in
  Cotype_parse.parse_status (Cotype_parse.json_or_raise r.stdout)

let read_base t ~file =
  (match ensure_init t ~file with
   | Ok () -> ()
   | Error msg -> raise_state msg);
  match open_ t ~file with
  | Ok r -> Persist.read_file r.base_path
  | Error msg -> raise_state msg

(* Production helper for ADR-010's append-clarification flow.
   Adapts our outcome types to [Clarification]'s mirror types. *)
let append_clarification t ~path ~questions =
  let adapt_open r : Clarification.cotype_open_result =
    { base_sha = r.base_sha; base_path = r.base_path;
      conflicted = r.conflicted }
  in
  let adapt_save_outcome = function
    | Direct s -> Clarification.Direct s
    | Merged s -> Clarification.Merged s
    | Noop -> Clarification.Noop
    | Conflict { conflict_path } ->
        Clarification.Conflict { conflict_path }
  in
  Clarification.append_via
    ~ensure_init:(fun ~file -> ensure_init t ~file)
    ~open_:(fun ~file -> Result.map adapt_open (open_ t ~file))
    ~save:(fun ~file ~base_sha ~actor ~bytes ->
      Result.map adapt_save_outcome
        (save t ~file ~base_sha ~actor ~bytes))
    ~path ~questions
