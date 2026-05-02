(** [Permissive_json] — pre-cleans agent JSON output per
    [conventions/context-economy.md] R7.

    This module is responsible for stripping markdown code fences,
    leading/trailing prose, and trailing commas before strict-validating
    against the [Characterization] schema. Pure; no I/O. *)

(** [extract s] returns the substring [s..] containing the first
    balanced JSON object, with light cleanup (trailing-comma squashing).

    @raise Error.K4k_error E_format if no balanced object is present. *)
val extract : string -> string

(** [parse s] = [Yojson.Safe.from_string (extract s)] with parse errors
    surfaced as [Error.K4k_error E_format]. Intended for the
    formalization-pass response parser; downstream
    [Characterization_decoder.of_yojson] is the strict validator. *)
val parse : string -> Yojson.Safe.t
