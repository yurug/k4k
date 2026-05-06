(** [Harness] — top-level k4k loop, parameterized by backend + verifier.

    This module is responsible for orchestrating the structural
    stability check and persisting [.k4k/manifest.json]. The semantic
    pass (step 2) lives in [Full_check]; the gap-step loop (step 3)
    will live in [Gap_step].

    The functor binds the backends so callers see a purely-functional
    interface; no global state. *)

(** Inputs to a [--check] invocation. *)
type check_inputs = {
  file_path : string;
  k4k_dir   : string;
  logger    : Logger.t;
  cotype    : Cotype.t option;
    (** Per ADR-010, when [Some t] every interaction-file read goes
        via [Cotype.open_] → [base_path]. When [None], direct reads
        are used (legacy path; retained for tests that don't shell
        out to the cotype binary). *)
}

(** Outcome of [check] / [full_check]. *)
type check_outcome =
  | Stable_structural        (** Structural-only pass (step-1 contract). *)
  | Stable_full              (** Structural + semantic pass (step-2). *)
  | Unstable                 (** Reserved for non-raising paths; v0 raises. *)

module type S = sig
  (** [check inputs] — runs the structural stability check and persists
      the manifest. Used directly by step-1 callers; step-2 callers go
      through [Full_check.run] instead.

      @raise Error.K4k_error on file/format/encoding/unstable.
      @invariant P10 — manifest is written atomically.
      @invariant P11 — only this function emits to stdout (via Logger). *)
  val check : check_inputs -> check_outcome
end

(** Functor binding a concrete backend and verifier. The step-1 call
    sites pass [Backend_stub] and [Verifier_stub]. *)
module Make (_ : Agent_backend.S) (_ : Verifier.S) : S
