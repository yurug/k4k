(** [Backend_stub] — deterministic in-memory agent backend for tests.

    This module is responsible for satisfying [Agent_backend.S] without
    touching the network. It implements P15 (pluggable backend
    conformance) and serves NF8 (weakness-profile enforcement) per Q3.3.

    Two profiles are supported:
    - [`Strong] — canned response returned verbatim.
    - [`Weak]   — same canned response but post-processed with markdown
                  code fences, trailing prose, and occasional trailing
                  commas to simulate a 7B-class local model. The
                  permissive parser ([Permissive_json]) tolerates these.

    [`Weak] is the *default* per [conventions/context-economy.md].

    Lookup: the first matching [(purpose, trigger)] wins. No match →
    [`Tool_error]. *)

type t

(** A single canned response entry. *)
type response_entry = {
  purpose : Agent_backend.purpose;
  trigger : string -> bool;
  payload : (string, [ `Budget_exhausted | `Tool_error of string ]) result;
}

type profile = [ `Strong | `Weak ]

type config = {
  responses : response_entry list;
  profile   : profile;
  weak_seed : int;     (** Deterministic seed for weak-profile jitter. *)
}

(** [default_config] — empty responses, profile [`Weak], seed [0]. *)
val default_config : config

(** ["stub"]. *)
val name : string

(** Fixed version string. *)
val version : t -> string

(** [create cfg] builds a stub backend.

    @invariant P15. *)
val create : config -> t

(** [invoke t ~purpose ~prompt ~budget] — looks up the first canned
    response whose [purpose] matches and whose [trigger prompt] is true;
    applies the weakness post-processing if [profile = `Weak].

    @invariant P15.
    @invariant NF8 — weak-profile post-processing is the default; tests
                     pass against it. *)
val invoke :
  t ->
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result
