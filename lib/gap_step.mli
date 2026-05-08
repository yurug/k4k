(** [Gap_step] — one full convergence iteration per
    [kb/spec/algorithms.md#gap-step] (v2 retrofit).

    Direct-commit workflow (ADR-013 §2 step 3, post-v2-batch-4a): the
    caller is responsible for being on the correct branch
    ([k4k/version/<n>]); [Gap_step] applies the agent's diff to the
    working tree, runs the verifier, and either commits-on-the-spot
    (Accepted) or [git reset --hard HEAD] (Rejected / Tradeoff).

    The previous v0/v1 scratch-branch indirection
    ([k4k/gap/<pid>/<ts>]) is gone; branches are managed by [Version]
    one level up.

    @invariant P5 — non-regression: a regressive patch is rejected.
    @invariant P6 — three-strikes-then-tradeoff (was: blocked).
    @invariant P9 — agent budget cap honored.
    @invariant P17 — no agent judgment on validity. *)

(** Type-erased dependency injection: closes over [Agent_backend.invoke]
    and [Verifier.run] without leaking the modules. *)
type 'b deps = {
  k4k_dir : string;
  workdir : string;
    (** The project working tree, already on [k4k/version/<n>]. *)
  agent_invoke :
    purpose:Agent_backend.purpose ->
    prompt:string -> budget:int -> Agent_backend.result;
  verifier_run :
    workdir:string -> focus:string list -> Verifier.run_result;
  logger : Logger.t;
  budget_remaining : int ref;
  agent_backend : 'b;
  tier : [ `A | `B | `C ];
    (** Tier the prompt is composed for; defaults to [`A] (ADR-011 §4). *)
}

(** Outcome of a single step. *)
type outcome =
  | Accepted of {
      property : Property.t;        (** updated; status = [`Established]. *)
      commit_sha : string;          (** SHA of the [\[k4k\] establish ...] commit. *)
    }
  | Rejected of {
      property : Property.t;        (** updated; failure_count bumped. *)
      reason : string;
    }
  | Blocked of Property.t           (** Pre-existing blocked / failure_count >= 3 short-circuit. *)
  | Tradeoff of {
      property : Property.t;        (** Reached 3 failures this turn — placeholder for batch-4b. *)
    }
  | Budget_exhausted

(** [step ~deps ~d ~current_summary ~prev_status ~property] — one
    iteration on the property [property] (the caller has already
    selected it via risk_score; v2's outer [Version_loop] does the
    selection).

    @param d desired characterization (used to compose the prompt).
    @param current_summary one-paragraph text rendering of the source.
    @param prev_status property→status map from the previous verifier
                       run; used for regression checks (P5).
    @param property the focus property; if its [failure_count] is
                    already [>= 3] or [blocked], returns [Blocked]
                    immediately.
    @raise Error.K4k_error E_state_corrupt on dirty tree / not-a-repo. *)
val step :
  deps:'b deps ->
  d:Characterization.t ->
  current_summary:string ->
  prev_status:(string * Verifier.status) list ->
  property:Property.t ->
  outcome
