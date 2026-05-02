(** [Full_check] — the step-2 entry point: structural + semantic
    stability + atomic persistence of [.k4k/characterization/desired/].

    Closes over a chosen [Agent_backend.S] module + a backend value
    constructed by the caller. *)

(** [run (module B) (module V) ~backend ~inputs] runs the structural
    check; if it passes, runs the semantic two-run protocol; if that
    passes (or hits the cache), runs coverage; if all pass, writes
    [desired/spec.json] + [desired/spec.md] atomically and updates the
    manifest. Returns the canonical [D].

    @raise Error.K4k_error E_unstable on any stability failure
                           (structural, semantic, coverage).
    @raise Error.K4k_error E_budget on agent-budget exhaustion at any
                           formalization call.
    @invariant P10 — every persistent write is atomic.
    @invariant P18 — the formalization runs at least twice on a miss.
    @invariant P19 — cache hit suppresses both calls. *)
val run :
  (module Agent_backend.S with type t = 'b) ->
  (module Verifier.S) ->
  backend:'b ->
  inputs:Harness.check_inputs ->
  Characterization.t
