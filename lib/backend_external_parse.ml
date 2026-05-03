(** [Backend_external_parse] — pure parser for the agent-backend wire-protocol
    JSON result file (see [kb/external/backend-protocol.md]). No I/O. *)

type outcome =
  | Ok_outcome
  | Budget_exhausted_outcome
  | Tool_error_outcome

type parsed = {
  outcome     : outcome;
  text        : string;        (* present iff outcome=Ok_outcome *)
  budget_used : int;           (* present iff outcome=Ok_outcome *)
  duration_ms : int;           (* always present *)
  error       : string;        (* present iff outcome=Tool_error_outcome *)
}

type error =
  | Invalid_json of string
  | Missing_field of string
  | Bad_outcome of string
  | Bad_type of string

let outcome_of_string = function
  | "ok"               -> Ok Ok_outcome
  | "budget_exhausted" -> Ok Budget_exhausted_outcome
  | "tool_error"       -> Ok Tool_error_outcome
  | other              -> Error other

let int_field fs key =
  match List.assoc_opt key fs with
  | Some (`Int n) -> Ok n
  | Some _ -> Error (Bad_type (key ^ " is not an int"))
  | None -> Error (Missing_field key)

let string_field fs key =
  match List.assoc_opt key fs with
  | Some (`String s) -> Ok s
  | Some _ -> Error (Bad_type (key ^ " is not a string"))
  | None -> Error (Missing_field key)

let validate_ok fs ~budget ~duration_ms =
  match string_field fs "text" with
  | Error e -> Error e
  | Ok text ->
      (match int_field fs "budget_used" with
       | Error e -> Error e
       | Ok used when used > budget ->
           Error (Bad_type
             (Printf.sprintf "budget_used=%d exceeds --budget=%d"
                used budget))
       | Ok used ->
           Ok { outcome = Ok_outcome; text; budget_used = used;
                duration_ms; error = "" })

let validate_tool_error fs ~duration_ms =
  match string_field fs "error" with
  | Error e -> Error e
  | Ok msg ->
      Ok { outcome = Tool_error_outcome; text = ""; budget_used = 0;
           duration_ms; error = msg }

let validate_budget_exhausted ~duration_ms =
  Ok { outcome = Budget_exhausted_outcome; text = "";
       budget_used = 0; duration_ms; error = "" }

let from_json ~budget (j : Yojson.Safe.t) : (parsed, error) result =
  match j with
  | `Assoc fs ->
      (match string_field fs "outcome" with
       | Error e -> Error e
       | Ok s ->
           (match outcome_of_string s with
            | Error other -> Error (Bad_outcome other)
            | Ok oc ->
                (match int_field fs "duration_ms" with
                 | Error e -> Error e
                 | Ok dur ->
                     match oc with
                     | Ok_outcome ->
                         validate_ok fs ~budget ~duration_ms:dur
                     | Budget_exhausted_outcome ->
                         validate_budget_exhausted ~duration_ms:dur
                     | Tool_error_outcome ->
                         validate_tool_error fs ~duration_ms:dur)))
  | _ -> Error (Bad_type "result is not a JSON object")

let parse ~budget (s : string) : (parsed, error) result =
  match Yojson.Safe.from_string s with
  | exception Yojson.Json_error msg -> Error (Invalid_json msg)
  | exception _ -> Error (Invalid_json "malformed JSON")
  | j -> from_json ~budget j

let render_error = function
  | Invalid_json s -> "invalid JSON in result: " ^ s
  | Missing_field k -> "result missing required field: " ^ k
  | Bad_outcome s ->
      Printf.sprintf "result.outcome: invalid value %S" s
  | Bad_type s -> "result has wrong type: " ^ s
