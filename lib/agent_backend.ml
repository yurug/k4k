(** [Agent_backend] — pluggable agent-backend signature.

    See [kb/spec/api-contracts.md#agent-backend]. The wire-protocol
    contract (ADR-009 / [kb/external/backend-protocol.md]) is what
    third-party backends conform to. v2 production wires
    [Backend_external] from [Watcher_dev.resolve_invoke];
    [Backend_canned] is the test-only adapter for canned responses
    via [K4K_STUB_RESPONSES].

    @invariant P15 — pluggability: nothing under [lib/] hardcodes a
                     specific agent toolchain. *)

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
