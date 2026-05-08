(** [Version_finalize] — version-completion + audit rendering helpers
    extracted from [Version_loop] (ADR-013 §2 step 5 / step 3 final).

    Pure-ish: render audit text, persist final manifest, optionally
    drive [Version.complete] (merge + tag) when every property is
    [established]. *)

(** Per-property outcome carried by [Version_loop]. *)
type prop_outcome = {
  id          : string;
  status      : string;
  commit_sha  : string option;
}

type emit_fn = string -> Yojson.Safe.t -> unit

(** [`Done] with the merged tag iff all outcomes were [established]
    and [Version.complete] succeeded; [`Rolled_back] otherwise. *)
type result =
  | Done of {
      tag       : string;
      tier_dist : Inline_blocks.tier_distribution;
    }
  | Rolled_back

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
