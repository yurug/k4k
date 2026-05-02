(** [Backend_stub] — deterministic in-memory agent backend for tests.

    This module is responsible for satisfying [Agent_backend.S] without
    touching the network. It implements P15 (pluggable backend conformance).

    Step 1 only: [invoke] always returns [`Tool_error "stub: step 1 doesn't
    call agents"]. Canned-response logic lands in step 2/3 per Q3.3.
*)

type t

(** Step-1 [config]. The [responses] field is reserved for step 2/3. *)
type response_entry = {
  purpose : Agent_backend.purpose;
  trigger : string -> bool;
  payload : (string, [ `Budget_exhausted | `Tool_error of string ]) result;
}

type config = {
  responses : response_entry list;
}

(** ["stub"]. *)
val name : string

(** [version t] — fixed version string [{"0.1.0-stub"}]. *)
val version : t -> string

(** [create cfg] builds a stub backend.

    @invariant P15. *)
val create : config -> t

(** [invoke t ~purpose ~prompt ~budget] — step 1 always returns
    [`Tool_error]; step 2/3 add lookup over [config.responses].

    @invariant P15. *)
val invoke :
  t ->
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result
