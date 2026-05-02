(** [Verifier_external_parse] — pure parser for the verifier wire-protocol
    JSON result file (see [kb/external/verifier-protocol.md]). No I/O. *)

type warning = { kind : string; message : string }

type parsed = {
  by_property   : (string * Verifier.status) list;
  raw_exit_code : int;
  duration_ms   : int;
  warnings      : warning list;
}

type error =
  | Invalid_json of string
  | Missing_field of string
  | Bad_status of string * string  (* prop_id, raw_status *)
  | Bad_type of string             (* describes which field is malformed *)

let status_of_string = function
  | "established"  -> Ok `Established
  | "contradicted" -> Ok `Contradicted
  | "unknown"      -> Ok `Unknown
  | other          -> Error other

let parse_by_property = function
  | `Assoc kvs ->
      let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | (pid, `String s) :: rest ->
            (match status_of_string s with
             | Ok st -> loop ((pid, st) :: acc) rest
             | Error other -> Error (Bad_status (pid, other)))
        | (pid, _) :: _ ->
            Error (Bad_type ("by_property[" ^ pid ^ "] not a string"))
      in
      loop [] kvs
  | _ -> Error (Bad_type "by_property is not an object")

let warning_of_json = function
  | `Assoc fs ->
      let kind = match List.assoc_opt "kind" fs with
        | Some (`String s) -> s
        | _ -> "" in
      let msg = match List.assoc_opt "message" fs with
        | Some (`String s) -> s
        | _ -> "" in
      { kind; message = msg }
  | _ -> { kind = ""; message = "" }

let parse_warnings = function
  | None -> []
  | Some (`List xs) -> List.map warning_of_json xs
  | Some _ -> []  (* tolerate misshaped warnings *)

let int_field fs key =
  match List.assoc_opt key fs with
  | Some (`Int n) -> Ok n
  | Some _ -> Error (Bad_type (key ^ " is not an int"))
  | None -> Error (Missing_field key)

let by_property_field fs =
  match List.assoc_opt "by_property" fs with
  | Some v -> parse_by_property v
  | None -> Error (Missing_field "by_property")

let from_json (j : Yojson.Safe.t) : (parsed, error) result =
  match j with
  | `Assoc fs ->
      (match by_property_field fs with
       | Error e -> Error e
       | Ok bp ->
           (match int_field fs "raw_exit_code" with
            | Error e -> Error e
            | Ok rec_ ->
                (match int_field fs "duration_ms" with
                 | Error e -> Error e
                 | Ok dur ->
                     let warns = parse_warnings
                       (List.assoc_opt "warnings" fs) in
                     Ok { by_property = bp;
                          raw_exit_code = rec_;
                          duration_ms = dur;
                          warnings = warns })))
  | _ -> Error (Bad_type "result is not a JSON object")

let parse (s : string) : (parsed, error) result =
  match Yojson.Safe.from_string s with
  | exception Yojson.Json_error msg -> Error (Invalid_json msg)
  | exception _ -> Error (Invalid_json "malformed JSON")
  | j -> from_json j

(* Pad missing focus IDs with [`Unknown]. Per the protocol: every key in
   [focus] must appear; missing IDs get Unknown. Extras are kept (not
   filtered) so callers can still see them in audit trails. *)
let with_focus_padding ~focus
    (bp : (string * Verifier.status) list) =
  let known = bp in
  if focus = [] then known
  else
    let augmented = List.fold_left (fun acc pid ->
      if List.mem_assoc pid acc then acc
      else (pid, `Unknown) :: acc) known focus
    in
    (* Stable order: focus first (in given order), then extras. *)
    let in_focus = List.filter_map (fun pid ->
      match List.assoc_opt pid augmented with
      | Some s -> Some (pid, s)
      | None -> None) focus in
    let extras = List.filter (fun (pid, _) ->
      not (List.mem pid focus)) augmented in
    in_focus @ extras

let render_error = function
  | Invalid_json s -> "invalid JSON in result: " ^ s
  | Missing_field k -> "result missing required field: " ^ k
  | Bad_status (pid, s) ->
      Printf.sprintf "result.by_property[%s]: invalid status %S" pid s
  | Bad_type s -> "result has wrong type: " ^ s
