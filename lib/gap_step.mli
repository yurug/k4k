(** [Gap_step] — one full convergence iteration per
    [kb/spec/algorithms.md#gap-step].

    This module is responsible for selecting the highest-risk property,
    asking the agent for a unified-diff, applying it on a fresh git
    scratch branch (Q3.2), running the verifier with [focus = [pid]],
    and accepting (FF-merge) iff the property becomes [Established] and
    no previously-established property regressed (P5).

    @invariant P5 — non-regression: a regressive patch is rejected.
    @invariant P6 — three-strikes-then-blocked.
    @invariant P9 — agent budget cap honored.
    @invariant P17 — no agent judgment on validity. *)

(** Type-erased dependency injection: closes over [Agent_backend.invoke]
    and [Verifier.run] without leaking the modules. *)
type 'b deps = {
  k4k_dir : string;
  workdir : string;
  agent_invoke :
    purpose:Agent_backend.purpose ->
    prompt:string -> budget:int -> Agent_backend.result;
  verifier_run :
    workdir:string -> focus:string list -> Verifier.run_result;
  logger : Logger.t;
  budget_remaining : int ref;
  agent_backend : 'b;
}

(** Outcome of a single step. *)
type outcome =
  | Accepted of Property.t           (** [property] now [Established]. *)
  | Rejected of Property.t * string  (** [property] with bumped fc. *)
  | Blocked of Property.t            (** failure_count >= 3; skip & log. *)
  | Budget_exhausted

(** [step ~deps ~d ~current_summary ~prev_status gap] — one iteration.

    @param d desired characterization (used to compose the prompt).
    @param current_summary one-paragraph text rendering of the source.
    @param prev_status property→status map from the previous verifier
                       run; used for regression checks (P5).
    @param gap the candidate properties; the highest-risk one is
               selected via [Property.argmax_lex].
    @raise Error.K4k_error E_state_corrupt on dirty tree / not-a-repo /
                            scratch-branch conflict (Q3.2). *)
val step :
  deps:'b deps ->
  d:Characterization.t ->
  current_summary:string ->
  prev_status:(string * Verifier.status) list ->
  Property.t list -> outcome
