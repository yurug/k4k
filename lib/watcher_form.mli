(** [Watcher_form] — v2 batch 4b: drives the real two-run formalization
    pass for the watcher's development half (replaces [K4K_TEST_D_PATH]).

    Structural stability MUST be checked by the caller before calling
    [run]; this module assumes the file already passes structural
    requirements (every required user-owned section present, non-empty).

    @invariant P18 — uses [Stability.semantic_check_with_backend], which
                     issues two formalization calls on a cache miss.
    @invariant P19 — cache short-circuit: equal user-section hashes +
                     a cached [D] on disk skips both calls.
    @invariant P10 — [.k4k/characterization/desired/spec.{json,md}] and
                     [.k4k/manifest.json] are written atomically. *)

type emit_fn = string -> Yojson.Safe.t -> unit

type agent_invoke =
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result

(** [run ~k4k_dir ~content ~agent_invoke ~emit] returns [Ok d] on
    success; [Error reason] when the spec is semantically unstable
    (formalization runs disagree, agent errors, coverage failures,
    etc). Side effects on success: writes
    [.k4k/characterization/desired/spec.{json,md}],
    [.k4k/manifest.json], and per-agent-run artefacts under
    [.k4k/agent-runs/<id>/]. *)
val run :
  k4k_dir:string ->
  content:string ->
  agent_invoke:agent_invoke ->
  emit:emit_fn ->
  (Characterization.t, string) result
