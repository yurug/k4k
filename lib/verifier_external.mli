(** [Verifier_external] — generic verifier adapter that invokes a
    configured external executable per
    [kb/external/verifier-protocol.md] and parses its JSON result.

    Implements [Verifier.S]. This is the only production verifier
    adapter k4k ships; per-tool specifics (regexes, exit-code maps)
    live inside the configured executable, never here. ADR-008. *)

type config = {
  command   : string list;        (** Executable + leading args; >= 1. *)
  timeout_s : int;                (** Wall-clock cap (default: 60s). *)
  k4k_dir   : string option;      (** Persist verifier-runs here. *)
  logger    : Logger.t option;    (** Sink for [verifier.warning]. *)
}

type t

val name : string
val version : t -> string
val default_config : config
val create : config -> t

val run :
  t ->
  workdir:string ->
  focus:string list ->
  Verifier.run_result
