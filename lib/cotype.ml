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

(* Run cotype with the given args; if the binary is missing, raise
   E_agent_unavailable with a clear hint. The cotype JSON envelope is
   on stdout; non-zero exit + valid JSON envelope is normal for
   conflict/error outcomes (callers parse the envelope). *)
let run_cotype ?stdin t ~args =
  try Subprocess.run ?stdin ~prog:t.cfg.binary ~args ~timeout_s:60 ()
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) ->
      raise_unavailable install_hint
  | Unix.Unix_error (e, _, _) ->
      raise_unavailable
        (Printf.sprintf "cotype subprocess error: %s" (Unix.error_message e))

let parse_json_or_raise raw =
  try Yojson.Safe.from_string raw
  with _ ->
    raise_state
      (Printf.sprintf "cotype: invalid JSON envelope: %s"
         (String.sub raw 0 (min 80 (String.length raw))))

let get_string field = function
  | `Assoc fs ->
      (match List.assoc_opt field fs with
       | Some (`String s) -> Some s | _ -> None)
  | _ -> None

let get_bool field = function
  | `Assoc fs ->
      (match List.assoc_opt field fs with
       | Some (`Bool b) -> Some b | _ -> None)
  | _ -> None

let envelope_status j =
  match get_string "status" j with
  | Some s -> s
  | None -> raise_state "cotype: envelope missing 'status' field"

let envelope_error j =
  let err = match get_string "error" j with Some s -> s | None -> "Error" in
  let msg = match get_string "message" j with Some s -> s | None -> "" in
  Printf.sprintf "%s: %s" err msg

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
  let j = parse_json_or_raise r.stdout in
  match envelope_status j with
  | "ok" -> Ok ()
  | "error" -> Error (envelope_error j)
  | s -> Error (Printf.sprintf "cotype init: unexpected status %s" s)

(* [open_] auto-initializes when the file is unmanaged (per the
   live-tested behavior of cotype 0.2.3); we therefore fold init into
   open's prelude as a no-op when already managed. *)
let ensure_init = init

type open_result = {
  base_sha  : string;
  base_path : string;
  conflicted : bool;
}

let parse_open_envelope j =
  let base_sha = match get_string "base_sha" j with
    | Some s -> s | None -> raise_state "cotype open: missing base_sha"
  in
  let base_path = match get_string "base_path" j with
    | Some s -> s | None -> raise_state "cotype open: missing base_path"
  in
  let conflicted = match get_bool "conflicted" j with
    | Some b -> b | None -> false
  in
  { base_sha; base_path; conflicted }

let open_ t ~file =
  let r = run_cotype t ~args:["open"; file; "--json"] in
  let j = parse_json_or_raise r.stdout in
  match envelope_status j with
  | "ok" -> Ok (parse_open_envelope j)
  | "error" -> Error (envelope_error j)
  | s -> Error (Printf.sprintf "cotype open: unexpected status %s" s)

type save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

let parse_save_envelope j =
  match envelope_status j with
  | "saved" ->
      let mode = match get_string "mode" j with
        | Some s -> s | None -> "direct" in
      let sha = match get_string "sha" j with Some s -> s | None -> "" in
      (match mode with
       | "direct"  -> Ok (Direct sha)
       | "merged"  -> Ok (Merged sha)
       | "noop"    -> Ok Noop
       | other -> Error (Printf.sprintf "cotype save: unknown mode %s" other))
  | "conflict" ->
      let cp = match get_string "conflict_path" j with
        | Some s -> s | None -> "" in
      Ok (Conflict { conflict_path = cp })
  | "error" -> Error (envelope_error j)
  | s -> Error (Printf.sprintf "cotype save: unexpected status %s" s)

let save t ~file ~base_sha ~actor ~bytes =
  let args =
    ["save"; file; "--base-sha"; base_sha; "--actor"; actor; "--json"] in
  let r = run_cotype t ~args ~stdin:bytes in
  let j = parse_json_or_raise r.stdout in
  parse_save_envelope j

let parse_status_envelope j =
  match envelope_status j with
  | "ok" ->
      (match get_string "state" j with
       | Some "unmanaged"  -> Ok `Unmanaged
       | Some "clean"      -> Ok `Clean
       | Some "conflicted" -> Ok `Conflicted
       | _ ->
           (* cotype 0.2.3 returns "status": "clean"|... directly without
              a "state" field. Fall back to that shape. *)
           (match get_string "status" j with
            | Some "unmanaged"  -> Ok `Unmanaged
            | Some "clean"      -> Ok `Clean
            | Some "conflicted" -> Ok `Conflicted
            | _ -> Error "cotype status: cannot parse state field"))
  | "unmanaged"  -> Ok `Unmanaged
  | "clean"      -> Ok `Clean
  | "conflicted" -> Ok `Conflicted
  | "error" -> Error (envelope_error j)
  | s -> Error (Printf.sprintf "cotype status: unexpected status %s" s)

let status t ~file =
  let r = run_cotype t ~args:["status"; file; "--json"] in
  let j = parse_json_or_raise r.stdout in
  parse_status_envelope j
