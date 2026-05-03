(** [Backend_external] — generic agent-backend adapter that invokes a
    configured external executable per
    [kb/external/backend-protocol.md] and parses its JSON result.

    Implements [Agent_backend.S]. This is the only production agent
    backend k4k ships; per-tool specifics (Anthropic SDK calls,
    Ollama HTTP requests, retry quirks) live inside the configured
    executable, never here. ADR-009. *)

type config = {
  command   : string list;        (** Executable + leading args; >= 1. *)
  timeout_s : int;                (** Wall-clock cap (default: 300s). *)
  k4k_dir   : string option;      (** Persist agent-runs here. *)
  logger    : Logger.t option;    (** Sink for [backend.*] events. *)
}

type t

val name : string
val version : t -> string
val default_config : config
val create : config -> t

(** [invoke t ~purpose ~prompt ~budget] — runs the configured backend
    with the rendered prompt and budget cap. Retries up to 3 times with
    exponential backoff (250/500/1000 ms) on transient tool errors
    (process exit != 0, missing/invalid output file).

    @invariant P15 — satisfies [Agent_backend.S]. *)
val invoke :
  t ->
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result
