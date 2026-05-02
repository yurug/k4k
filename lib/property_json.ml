(** [Property_json] — encode/decode [Property.t] records to/from
    [Yojson.Safe.t] per [kb/spec/data-model.md#property] and
    [config-and-formats.md#k4kgapproperties.json].

    Pure; no I/O. *)

let status_to_string : Property.status -> string = function
  | `Required -> "required"
  | `Established -> "established"
  | `Contradicted -> "contradicted"
  | `Unknown -> "unknown"

let status_of_string = function
  | "required" -> `Required
  | "established" -> `Established
  | "contradicted" -> `Contradicted
  | "unknown" -> `Unknown
  | s -> raise (Error.K4k_error
                  (Error.E_state_corrupt
                     (Printf.sprintf "unknown property status: %s" s)))

let kind_to_string : Property.artefact_kind -> string = function
  | `Agent_run -> "agent-run"
  | `Verifier_run -> "verifier-run"

let kind_of_string = function
  | "agent-run" -> `Agent_run
  | "verifier-run" -> `Verifier_run
  | s -> raise (Error.K4k_error
                  (Error.E_state_corrupt
                     (Printf.sprintf "unknown artefact kind: %s" s)))

let ref_to_yojson (r : Property.artefact_ref) : Yojson.Safe.t =
  `Assoc [ "kind", `String (kind_to_string r.kind);
           "id",   `String r.ref_id ]

let ref_of_yojson : Yojson.Safe.t -> Property.artefact_ref = function
  | `Assoc fs ->
      let kind = match List.assoc_opt "kind" fs with
        | Some (`String s) -> kind_of_string s
        | _ -> raise (Error.K4k_error
                        (Error.E_state_corrupt "artefact_ref: missing kind"))
      in
      let ref_id = match List.assoc_opt "id" fs with
        | Some (`String s) -> s | _ -> "" in
      { kind; ref_id }
  | _ -> raise (Error.K4k_error
                  (Error.E_state_corrupt "artefact_ref: not an object"))

let aspect_to_yojson (a : Property.aspect_ref) : Yojson.Safe.t =
  `Assoc [ "aspect", `String a.aspect;
           "path",   `List (List.map (fun s -> `String s) a.path) ]

let aspect_of_yojson : Yojson.Safe.t -> Property.aspect_ref = function
  | `Assoc fs ->
      let aspect = match List.assoc_opt "aspect" fs with
        | Some (`String s) -> s | _ -> "" in
      let path = match List.assoc_opt "path" fs with
        | Some (`List xs) ->
            List.map (function `String s -> s | _ -> "") xs
        | _ -> [] in
      { aspect; path }
  | _ -> raise (Error.K4k_error
                  (Error.E_state_corrupt "aspect_ref: not an object"))

let to_yojson (p : Property.t) : Yojson.Safe.t =
  `Assoc [
    "id",            `String p.id;
    "statement",     `String p.statement;
    "status",        `String (status_to_string p.status);
    "evidence",      `List (List.map ref_to_yojson p.evidence);
    "risk_score",    `Float p.risk_score;
    "failure_count", `Int p.failure_count;
    "blocked",       `Bool p.blocked;
    "source",        aspect_to_yojson p.source;
  ]

let of_yojson : Yojson.Safe.t -> Property.t = function
  | `Assoc fs ->
      let s = function `String s -> s | _ -> "" in
      let i = function `Int i -> i | _ -> 0 in
      let b = function `Bool b -> b | _ -> false in
      let f = function `Float f -> f | `Int i -> float_of_int i | _ -> 0.0 in
      let assoc k = List.assoc_opt k fs in
      let id = match assoc "id" with Some v -> s v | None -> "" in
      let statement = match assoc "statement" with Some v -> s v | None -> "" in
      let status = match assoc "status" with
        | Some (`String s) -> status_of_string s
        | _ -> `Required in
      let evidence = match assoc "evidence" with
        | Some (`List xs) -> List.map ref_of_yojson xs | _ -> [] in
      let risk_score = match assoc "risk_score" with Some v -> f v | None -> 0.0 in
      let failure_count = match assoc "failure_count" with
        | Some v -> i v | None -> 0 in
      let blocked = match assoc "blocked" with Some v -> b v | None -> false in
      let source = match assoc "source" with
        | Some v -> aspect_of_yojson v
        | None -> { aspect = ""; path = [] } in
      { Property.id; statement; status; evidence; risk_score;
        failure_count; blocked; source }
  | _ -> raise (Error.K4k_error
                  (Error.E_state_corrupt "property: not an object"))

(** Encode a list of properties as a [{"count": N, "items": [...]}] JSON
    object, written canonically. *)
let list_to_yojson (ps : Property.t list) : Yojson.Safe.t =
  `Assoc [
    "count", `Int (List.length ps);
    "items", `List (List.map to_yojson ps);
  ]

let list_of_yojson : Yojson.Safe.t -> Property.t list = function
  | `Assoc fs ->
      (match List.assoc_opt "items" fs with
       | Some (`List xs) -> List.map of_yojson xs
       | _ -> [])
  | `List xs -> List.map of_yojson xs
  | _ -> raise (Error.K4k_error
                  (Error.E_state_corrupt "gap properties: malformed"))
