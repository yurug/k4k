(** [Version_finalize] — version-completion + audit rendering helpers
    extracted from [Version_loop] (ADR-013 §2 step 5 / step 3 final).

    Pure-ish: render audit text, persist final manifest, optionally
    drive [Version.complete] (merge + tag) when every property is
    [established]. *)

(** Per-property outcome carried by [Version_loop]. [failure_reason]
    is set when the property reached a deferred / blocked state with
    a known cause (the last gap-step's rejection reason); used by
    the watcher to surface the cause to the user via a clarification
    block on a rolled-back version (Ralph-loop step 2, v2 batch 27). *)
type prop_outcome = {
  id             : string;
  status         : string;
  commit_sha     : string option;
  failure_reason : string option;
}

type emit_fn = string -> Yojson.Safe.t -> unit

(** [`Done] with the merged tag iff all outcomes were [established]
    and [Version.complete] succeeded; [`Rolled_back] otherwise. The
    [Rolled_back] payload carries the per-property outcomes so the
    watcher can surface a summary clarification to the user
    (v2 batch 27 Ralph-loop step 2). *)
type result =
  | Done of {
      tag       : string;
      tier_dist : Inline_blocks.tier_distribution;
    }
  | Rolled_back of { outcomes : prop_outcome list }

(** [finalize ~cwd ~k4k_dir ~default_branch ~delete_branch ~emit
        ~v ~outcomes ~started_at ?cotype ()] writes the final
    [manifest.json] + [audit.md]; on full success drives
    [Version.complete] (merge + tag) and returns [Done]. *)
val finalize :
  cwd:string ->
  k4k_dir:string ->
  default_branch:string ->
  delete_branch:bool ->
  emit:emit_fn ->
  v:Version.t ->
  outcomes:prop_outcome list ->
  started_at:float ->
  ?cotype:Cotype.t ->
  unit ->
  result
