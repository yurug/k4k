(** [Verifier_dune_ocaml] — v0 verifier adapter for OCaml/dune projects.

    This module is responsible for:
    - invoking [dune build @runtest --force --display=quiet] on a target
      [workdir];
    - parsing alcotest output (per [external/dune.md]) into property-
      keyed statuses;
    - persisting [stdout.log], [stderr.log], [result.json] under
      [.k4k/verifier-runs/<id>/];
    - logging [verifier.warning] events for tests whose names violate
      the [P<id>_<slug>] convention (T20).

    Implements [Verifier.S]. P15 (pluggability), T20, NF7. *)

type config = {
  dune_binary : string;          (** Default: ["dune"]. *)
  timeout_s   : int;             (** Wall-clock cap (default: 60s). *)
  k4k_dir     : string option;   (** Persist verifier-runs here, if set. *)
  logger      : Logger.t option; (** Sink for [verifier.warning] events. *)
}

type t

val name : string
val version : t -> string
val create : config -> t

(** [warnings t] — list of [(test_name, reason)] surfaced by the most
    recent [run]. Used by tests; not part of [Verifier.S]. *)
val warnings : t -> (string * string) list

val default_config : config

val run :
  t ->
  workdir:string ->
  focus:string list ->
  Verifier.run_result
