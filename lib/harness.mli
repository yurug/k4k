(** [Harness] — top-level k4k loop, parameterized by backend + verifier.

    This module is responsible for orchestrating the structural-stability
    check, persisting [.k4k/manifest.json] and [.k4k/log.jsonl], and
    deciding the exit-code path. It implements P11 (stdout/stderr discipline)
    and P15 (purely calls the abstract backends).

    Step 1: [check] is the only entry point; [run] (full convergence loop)
    lands in step 3. The functor binds the backends so callers see a
    purely-functional interface; no global state.
*)

(** Inputs to a [--check] invocation. *)
type check_inputs = {
  file_path : string;        (* path to the user's [.k4k] file *)
  k4k_dir   : string;        (* path to the .k4k directory (typically [.k4k]) *)
  logger    : Logger.t;
}

(** Outcome of [check]. The CLI maps this to an exit code. *)
type check_outcome =
  | Stable_structural        (* exit 0; stdout: "stable (structural-only)" *)
  | Unstable                 (* exit 1; details on stderr *)

module type S = sig
  (** [check inputs] — runs the structural stability check, persists
      [.k4k/manifest.json] and emits [stability.start] / [stability.pass]
      or [stability.fail] events.

      @raise Error.K4k_error on file/format/encoding errors.
      @invariant P10 — manifest is written atomically.
      @invariant P11 — only this function emits to stdout. *)
  val check : check_inputs -> check_outcome
end

(** Functor binding a concrete backend and verifier. The step-1 call sites
    pass [Backend_stub] and [Verifier_stub]. *)
module Make (_ : Agent_backend.S) (_ : Verifier.S) : S
