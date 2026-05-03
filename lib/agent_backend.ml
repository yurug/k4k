(** [Agent_backend] — pluggable agent backend signature.

    See [kb/spec/api-contracts.md#agent-backend]. The only production
    implementation is [Backend_external] (per ADR-009 / the wire
    protocol in [kb/external/backend-protocol.md]); [Backend_stub] is
    used in tests. [Harness] is a functor over this signature.
*)

type purpose = [ `Formalization | `Gap_step | `Kb_regen ]

type response = {
  text        : string;
  budget_used : int;
  duration_ms : int;
}

type result =
  [ `Ok of response
  | `Budget_exhausted
  | `Tool_error of string ]

module type S = sig
  type t
  type config

  val name : string
  val version : t -> string
  val create : config -> t

  val invoke :
    t ->
    purpose:purpose ->
    prompt:string ->
    budget:int ->
    result
end
