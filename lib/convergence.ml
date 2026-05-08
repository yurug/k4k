(** [Convergence] — engine entry point invoked by the v2 watcher
    (ADR-011). Pre-v2 it was the [k4k <file.k4k>] direct entry.

    Wires [Full_check.run] (semantic stability + D persistence) to the
    [Run_loop.run] convergence driver. Closes over the chosen
    [Agent_backend.S] + [Verifier.S] modules.

    @invariant P13 — file re-read at every step (delegated). *)

let raise_state msg =
  raise (Error.K4k_error (Error.E_state_corrupt msg))

let make_deps (type b) (type v)
    (module B : Agent_backend.S with type t = b)
    (module V : Verifier.S with type t = v)
    ~backend ~verifier ~inputs ~budget_ref : _ Gap_step.deps =
  {
    k4k_dir = inputs.Harness.k4k_dir;
    workdir = ".";
    agent_invoke = (fun ~purpose ~prompt ~budget ->
      B.invoke backend ~purpose ~prompt ~budget);
    verifier_run = (fun ~workdir ~focus ->
      V.run verifier ~workdir ~focus);
    logger = inputs.Harness.logger;
    budget_remaining = budget_ref;
    agent_backend = backend;
  }

let run (type b) (type v)
    (module B : Agent_backend.S with type t = b)
    (module V : Verifier.S with type t = v)
    ~(backend : b) ~(verifier : v)
    ~(inputs : Harness.check_inputs)
    ~(cfg : Run_loop.config) : Harness.check_outcome =
  Sigint.install ();
  Persist.ensure_dir inputs.k4k_dir;
  let d = Full_check.run (module B) (module V)
            ~verifier ~backend ~inputs () in
  if not (Git.is_repo ~cwd:".") then
    raise_state
      "convergence: working directory is not a git repo (run 'git init')";
  Logger.info inputs.logger "loop.start"
    (`Assoc [ "max_steps", `Int cfg.max_steps;
              "budget", `Int cfg.budget ]);
  let initial_gap = Property.from_characterization d in
  let budget_ref = ref cfg.budget in
  let deps = make_deps (module B) (module V)
               ~backend ~verifier ~inputs ~budget_ref in
  let _ : Run_loop.result =
    Run_loop.run ~file_path:inputs.file_path
      ~deps ~d ~cfg ~k4k_dir:inputs.k4k_dir
      ~logger:inputs.logger ~initial_gap ()
  in
  Stable_full
