(** [Convergence] — step-3 entry point for [k4k <file.k4k>] (no
    [--check]).

    Runs the full pipeline: stability check + D persistence (via
    [Full_check.run]) followed by the iterative gap-step convergence
    loop ([Run_loop.run]). Closes over the chosen [Agent_backend.S] and
    [Verifier.S] modules.

    @raise Error.K4k_error E_unstable, E_budget, E_max_steps,
                            E_state_corrupt, E_verifier_tool_error. *)

val run :
  (module Agent_backend.S with type t = 'b) ->
  (module Verifier.S with type t = 'v) ->
  backend:'b ->
  verifier:'v ->
  inputs:Harness.check_inputs ->
  cfg:Run_loop.config ->
  Harness.check_outcome
