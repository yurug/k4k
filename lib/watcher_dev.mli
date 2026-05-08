(** [Watcher_dev] — development-half of the watcher (ADR-011 §6,
    ADR-013 §2). Invoked from [Watcher_loop] when stability passes;
    drives [Version_loop] which owns the gap-step loop and git lifecycle.

    v2 batch 4b: real formalization replaces the [K4K_TEST_D_PATH] knob.
    The agent backend (canned in tests, [Backend_external] in production)
    is reused for both the formalization pass and the gap-step loop. *)

type emit_fn = string -> Yojson.Safe.t -> unit

(** [resolve_invoke ~emit] resolves the agent-invoke closure ONCE per
    watcher run. Reuse the same closure across every
    [try_run_version] call: the canned backend ([Backend_canned])
    holds per-purpose queues internally, and re-loading the canned
    JSON on every iteration would reset those queues — formalize
    would then always return the first canned payload regardless of
    how many versions have already consumed responses. Production
    swaps in [Backend_external] (which is stateless w.r.t. iteration
    count and tolerates re-allocation, but the same single-allocation
    discipline keeps the watcher uniform). *)
val resolve_invoke :
  emit:emit_fn ->
  Version_loop.agent_invoke

(** [try_run_version ~file_path ~k4k_dir ~emit ~agent_invoke ct]:
    - [`Done] when the version completed (all properties established,
      merged + tagged);
    - [`Rolled_back] when the version-loop rolled back (some
      properties deferred / blocked) or raised;
    - [`Skipped] when no version was attempted (formalize error or
      idempotence gate via [last_completed_d_hash]).

    [`Done] and [`Rolled_back] are both terminal version outcomes;
    [`Skipped] is non-terminal. The watcher's main loop counts the
    terminal outcomes against [max_versions] and treats either as
    sufficient to satisfy [exit_on_done]. *)
val try_run_version :
  file_path:string ->
  k4k_dir:string ->
  emit:emit_fn ->
  agent_invoke:Version_loop.agent_invoke ->
  Cotype.t ->
  [ `Done | `Rolled_back | `Skipped ]

(** Splice a [state: done] status block into the file via cotype save. *)
val after_version_done :
  file_path:string ->
  Cotype.t ->
  version_n:int ->
  tier_dist:Inline_blocks.tier_distribution ->
  unit

(* Note: the P22 drift counter that previously lived here was moved
   to [Version_user_edits.count_drift] now that the user-edits
   queueing is wired into [Version_loop.run_gap_loop]. *)
