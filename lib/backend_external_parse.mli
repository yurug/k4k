(** [Backend_external_parse] — pure parser for the wire-protocol result
    JSON (see [kb/external/backend-protocol.md]). *)

type outcome =
  | Ok_outcome
  | Budget_exhausted_outcome
  | Tool_error_outcome

type parsed = {
  outcome     : outcome;
  text        : string;
  budget_used : int;
  duration_ms : int;
  error       : string;
}

type error =
  | Invalid_json of string
  | Missing_field of string
  | Bad_outcome of string
  | Bad_type of string

(** [parse ~budget raw] parses the result JSON and validates the schema.
    Validation errors include: missing required fields, wrong types,
    [outcome] not one of the three literals, [budget_used > budget]. *)
val parse : budget:int -> string -> (parsed, error) result

val render_error : error -> string
