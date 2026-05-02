(** [Backend_claude] — subprocess agent backend per
    [kb/external/claude-code.md].

    This module is responsible for satisfying [Agent_backend.S] via
    [claude -p]. It implements the budget cap (P9 — refuses pre-call when
    [used + budget > hard_per_invocation]), the retry policy
    (transient-error backoff up to [max_retries], counting toward
    budget), and the failure mapping (missing binary →
    EAGENT_UNAVAILABLE, auth errors → EAGENT_UNAVAILABLE).

    Live invocation is gated by env [K4K_LIVE=1] in tests; CI never
    runs it. *)

type t

type config = {
  binary              : string;     (** "claude" by default *)
  hard_per_invocation : int;        (** preset budget cap *)
  max_retries         : int;
}

(** [default_config]: binary = ["claude"], cap = 1000, retries = 3. *)
val default_config : config

(** ["claude-code"]. *)
val name : string

(** Captured at create time from [claude --version]. *)
val version : t -> string

(** [create cfg] probes [claude --version] (best-effort) and returns
    a fresh backend. Spending starts at [0]. *)
val create : config -> t

(** [invoke t ~purpose ~prompt ~budget] — runs the subprocess and
    parses its JSON wrapper.

    @invariant P9 — pre-call refusal when [used+budget > cap].
    @invariant P15 — satisfies [Agent_backend.S]. *)
val invoke :
  t ->
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result
