(** [Watcher_dev] — development-half of the watcher (ADR-011 §6,
    ADR-013 §2). Invoked from [Watcher_loop] when stability passes;
    drives [Version_loop] which owns the gap-step loop and git lifecycle.

    v2 batch 4b: real formalization replaces the [K4K_TEST_D_PATH] knob.
    The agent backend (canned in tests, [Backend_external] in production)
    is reused for both the formalization pass and the gap-step loop. *)

type emit_fn = string -> Yojson.Safe.t -> unit

(** [try_run_version ~file_path ~k4k_dir ~emit ct] returns [`Done] if
    a version completed successfully, [`Pending] otherwise (rollback,
    or no D available). *)
val try_run_version :
  file_path:string ->
  k4k_dir:string ->
  emit:emit_fn ->
  Cotype.t ->
  [ `Done | `Pending ]

(** Splice a [state: done] status block into the file via cotype save. *)
val after_version_done :
  file_path:string ->
  Cotype.t ->
  version_n:int ->
  tier_dist:Inline_blocks.tier_distribution ->
  unit

(** P22 helper: count user-owned sections whose hash differs between
    [baseline_hashes] (snapshot at version-N stabilization) and
    [current_hashes] (most recent read). *)
val pending_user_edits :
  baseline_hashes:(string * string) list ->
  current_hashes:(string * string) list ->
  int
