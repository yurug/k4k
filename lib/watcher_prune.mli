(** [Watcher_prune] — file-pruning rules per ADR-011 §7.

    @invariant P1 — every interaction-file mutation flows through
                    [Cotype.save].

    Idempotent: running [run] repeatedly on a stable spec converges
    to a fixed point (clarification breadcrumbs replace blocks,
    welcome stays gone). *)

(** [run ~ct ~file_path ~k4k_dir ~emit] — apply clarification
    archival + welcome auto-delete in a single cotype save (or none
    when nothing changed). *)
val run :
  ct:Cotype.t ->
  file_path:string ->
  k4k_dir:string ->
  emit:(string -> Yojson.Safe.t -> unit) ->
  unit

(** [prune_clarifications_in ~k4k_dir content] — pure helper exposed
    for unit tests. Returns [Some bytes'] when at least one
    clarification was archived (and replaces it with a breadcrumb);
    [None] when nothing changed. Side effect: archives the original
    block bytes to [.k4k/clarifications/<ts>.md] (or the per-version
    dir when an in-flight version exists). *)
val prune_clarifications_in :
  k4k_dir:string -> string -> string option

(** [maybe_delete_welcome content] — pure helper exposed for unit
    tests. Returns [Some bytes'] when the welcome block should be
    deleted (no version block exists yet AND ≥1 resolved-clarification
    breadcrumb is present); [None] otherwise. *)
val maybe_delete_welcome : string -> string option
