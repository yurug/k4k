(** [Verifier_external_parse] — pure parser for the wire-protocol result
    JSON (see [kb/external/verifier-protocol.md]). *)

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
  | Bad_status of string * string
  | Bad_type of string

val parse : string -> (parsed, error) result

(** [with_focus_padding ~focus bp] returns [bp] with every ID in [focus]
    that was absent appended as [`Unknown]. Order: focus order first,
    then extras. *)
val with_focus_padding :
  focus:string list ->
  (string * Verifier.status) list ->
  (string * Verifier.status) list

val render_error : error -> string
