(** [Rollback_feedback] — Ralph-loop steps 2 + 3 (v2 batches 27, 28).

    When a version rolls back, [post_rollback_clarification]
    splices a clarification block summarizing the deferred
    properties + their last failure reasons. When N consecutive
    rollbacks happen (no [Done] in between),
    [escalate_unsatisfiable_streak] adds a stronger clarification
    naming the streak count and suggesting user actions.

    Both helpers are best-effort: cotype-write failures surface as
    [clarification.write_failed] events. The watcher continues
    polling either way — we don't forfeit autonomy on rollback. *)

type emit_fn = string -> Yojson.Safe.t -> unit

(** Threshold the watcher uses for [escalate_unsatisfiable_streak]. *)
val streak_threshold : int

(** [post_rollback_clarification ~ct ~file_path ~emit ~outcomes]
    splices a [## k4k:clarification:*] block listing every
    deferred / blocked property in [outcomes] with its
    [failure_reason]. Emits
    [clarification.rolled_back_summary] with the count + ids on
    success, or [clarification.write_failed] on failure. No-op
    when [outcomes] contains no non-established entries. *)
val post_rollback_clarification :
  ct:Cotype.t ->
  file_path:string ->
  emit:emit_fn ->
  outcomes:Version_finalize.prop_outcome list ->
  unit

(** [escalate_unsatisfiable_streak ~ct ~file_path ~emit ~streak]
    splices a stronger clarification when [streak] consecutive
    versions have rolled back. Emits
    [version.unsatisfiable_streak] with the streak count + the
    [streak_threshold]. *)
val escalate_unsatisfiable_streak :
  ct:Cotype.t ->
  file_path:string ->
  emit:emit_fn ->
  streak:int ->
  unit
