(** [Cotype_parse] — pure helpers that decode cotype's --json
    envelopes. Split out of [Cotype] to keep that file under the
    200-line code-style cap. *)

let raise_state msg =
  raise (Error.K4k_error (Error.E_state_corrupt msg))

let json_or_raise raw =
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

type open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

let parse_open j =
  match envelope_status j with
  | "ok" ->
      let base_sha = match get_string "base_sha" j with
        | Some s -> s | None -> raise_state "cotype open: missing base_sha"
      in
      let base_path = match get_string "base_path" j with
        | Some s -> s | None -> raise_state "cotype open: missing base_path"
      in
      let conflicted = match get_bool "conflicted" j with
        | Some b -> b | None -> false in
      Ok { base_sha; base_path; conflicted }
  | "error" -> Error (envelope_error j)
  | s -> Error (Printf.sprintf "cotype open: unexpected status %s" s)

type save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

let parse_save j =
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

let parse_status j =
  match envelope_status j with
  | "ok" ->
      (match get_string "state" j with
       | Some "unmanaged"  -> Ok `Unmanaged
       | Some "clean"      -> Ok `Clean
       | Some "conflicted" -> Ok `Conflicted
       | _ ->
           (* cotype 0.2.3 returns "status": "clean"|... directly. *)
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

let parse_init j =
  match envelope_status j with
  | "ok" -> Ok ()
  | "error" -> Error (envelope_error j)
  | s -> Error (Printf.sprintf "cotype init: unexpected status %s" s)
