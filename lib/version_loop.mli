(** [Version_loop] — orchestrates the per-version development cycle
    on top of [Version] (git lifecycle), [Version_persist] (disk),
    and [Audit_md] (rendering).

    Used by [Watcher_loop] when stability succeeds. The implementation
    is deliberately small for v2 batch 3: it cuts a branch, persists
    [D-spec.json] + [manifest.json], drives an accept-only gap loop
    (each property gets one commit with [\[k4k\] establish <pid>]),
    completes via merge + tag + branch delete, and renders [audit.md].

    The agent / verifier surface is kept stub-compatible so integration
    tests can drive it without a real LLM. v2 batch 4 will widen this
    out to invoke [Convergence] proper for real Tier-A proofs. *)

type config = {
  cwd            : string;
    (** The user's project working directory (where [git] runs). *)
  k4k_dir        : string;
  default_branch : string;
  emit           : string -> Yojson.Safe.t -> unit;
    (** JSONL emitter — same signature as [Watcher_loop.config.emit]. *)
  delete_branch_on_done : bool;
    (** ADR-013 §2 step 5: default behaviour deletes the version branch
        after merge. Set [false] to honour
        [k4k.keep_version_branches: true] frontmatter. *)
}

type result =
  | Done of {
      tag       : string;
      tier_dist : Inline_blocks.tier_distribution;
    }
  | Rolled_back

(** [run ~cfg ~baseline_sha ~d ?cotype ()] drives one version end to
    end. Emits [version.start], [version.commit] (one per property),
    [version.complete] / [version.complete_error] events through
    [cfg.emit]. *)
val run :
  cfg:config ->
  baseline_sha:string ->
  d:Characterization.t ->
  ?cotype:Cotype.t ->
  unit -> result
