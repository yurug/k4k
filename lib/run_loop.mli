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
  between_steps : (unit -> unit) option;
    (** Test hook: invoked between gap-steps. Used by T4. *)
}

type result = {
  steps_run : int;
  final_gap : Property.t list;
  converged : bool;
}

val default_config : config

(** [initial_user_hashes path] — read [path] (if any) and return the
    user-section hashes, or [[]] on missing-file / parse failure.
    Exposed for unit-testing the T4 mid-run-edit hook. *)
val initial_user_hashes : string option -> (string * string) list

(** [run ?file_path ~deps ~d ~cfg ~k4k_dir ~logger ~initial_gap ()] —
    drive the loop until convergence / blocked / budget / max-steps.

    @param file_path Optional [<file.k4k>] for P13 mid-run-edit
                     detection (T4). When provided, the file is
                     re-read at the start of every step; if the user
                     section hashes change, a [stability.start]
                     event is logged.
    @raise Error.K4k_error E_max_steps when the step cap is hit.
    @raise Error.K4k_error E_budget on hard-cap exhaustion.
    @invariant P13 — file re-read at every step. *)
val run :
  ?file_path:string ->
  deps:'b Gap_step.deps ->
  d:Characterization.t ->
  cfg:config ->
  k4k_dir:string ->
  logger:Logger.t ->
  initial_gap:Property.t list ->
  unit ->
  result
