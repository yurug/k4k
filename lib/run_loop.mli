(** [Run_loop] — top-level step-3 convergence loop.

    Drives [Gap_step.step] until the gap is empty, all remaining
    properties are blocked, the [--max-steps] cap is reached
    ([E_max_steps]), or the budget is exhausted ([E_budget]).

    Persists [.k4k/gap/properties.json] after every step.

    @invariant P5 — non-regression (delegated to [Gap_step]).
    @invariant P9 — budget cap honored.
    @invariant NF7 — every state-changing event is logged. *)

type config = {
  max_steps : int;
  budget    : int;
}

type result = {
  steps_run : int;
  final_gap : Property.t list;
  converged : bool;
}

val default_config : config

(** [run ~deps ~d ~cfg ~k4k_dir ~logger ~initial_gap] — drive the loop
    until convergence / blocked / budget / max-steps.

    @raise Error.K4k_error E_max_steps when the step cap is hit.
    @raise Error.K4k_error E_budget on hard-cap exhaustion. *)
val run :
  deps:'b Gap_step.deps ->
  d:Characterization.t ->
  cfg:config ->
  k4k_dir:string ->
  logger:Logger.t ->
  initial_gap:Property.t list ->
  result
