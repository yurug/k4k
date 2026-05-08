(** [Verifier] — pluggable verifier signature.

    See [kb/spec/api-contracts.md#verifier]. v2 production wires
    [Verifier_external] (the wire-protocol adapter, ADR-008);
    [Verifier_stub] is a test-only deterministic adapter still
    referenced by the unit suite. Per ADR-012, the agent emits the
    wrapper script + tooling choice per project; k4k carries no
    reference verifier example. *)

type status = [ `Established | `Contradicted | `Unknown ]

type result_ok = {
  by_property   : (string * status) list;
  raw_exit_code : int;
  stdout_path   : string;
  stderr_path   : string;
  duration_ms   : int;
}

type run_result =
  [ `Ok of result_ok
  | `Tool_error of string ]

module type S = sig
  type t
  type config

  val name : string
  val version : t -> string
  val create : config -> t

  val run :
    t ->
    workdir:string ->
    focus:string list ->
    run_result
end
