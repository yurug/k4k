(** [Property_json] — JSON encoders/decoders for [Property.t] per
    [kb/spec/data-model.md#property]. Pure; no I/O. *)

val to_yojson : Property.t -> Yojson.Safe.t

val of_yojson : Yojson.Safe.t -> Property.t

(** [list_to_yojson ps] = [{"count": N, "items": [...]}]. *)
val list_to_yojson : Property.t list -> Yojson.Safe.t

val list_of_yojson : Yojson.Safe.t -> Property.t list

(** Helpers exposed for tests. *)
val status_to_string : Property.status -> string
val status_of_string : string -> Property.status
