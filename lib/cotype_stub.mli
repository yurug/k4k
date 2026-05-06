(** [Cotype_stub] — in-memory stub mirroring [Cotype].

    Used by unit tests that don't want to shell out to the cotype
    binary. The integration tests (S1, T8) use the real [Cotype]. *)

type config = {
  binary : string;
  conflict_on_save : bool;     (** Force every [save] to return Conflict. *)
  fixed_version    : string;
}

val default_config : config

type t

val name : string
val version : t -> string
val create : config -> t

val init : t -> file:string -> (unit, string) result
val ensure_init : t -> file:string -> (unit, string) result

type open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

val open_ : t -> file:string -> (open_result, string) result

type save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

val save : t -> file:string -> base_sha:string -> actor:string ->
           bytes:string -> (save_outcome, string) result

val status : t -> file:string ->
             ([ `Unmanaged | `Clean | `Conflicted ], string) result
