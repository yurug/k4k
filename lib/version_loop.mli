(** [Version_loop] — orchestrates the per-version development cycle
    on top of [Version] (git lifecycle), [Version_persist] (disk),
    [Gap_step] (per-property convergence), and [Audit_md] (rendering).

    Used by [Watcher_loop] when stability succeeds. v2 batch 4a
    direct-commit workflow (ADR-013 §2 step 3): each accepted gap-step
    commits with [\[k4k\] establish <pid>] on the version branch; on
    rejection the working tree is rewound via [git reset --hard HEAD]
    inside [Gap_step]. *)

(** Per-property gap-step driver. Closures hide the
    [Agent_backend] / [Verifier] modules so this file is independent of
    the concrete backends. *)
type agent_invoke =
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result

type verifier_run =
  workdir:string ->
  focus:string list ->
  Verifier.run_result

type config = {
  cwd            : string;
    (** The user's project working directory (where [git] runs and
        where the version branch is checked out). *)
  k4k_dir        : string;
  default_branch : string;
  emit           : string -> Yojson.Safe.t -> unit;
    (** JSONL emitter — same signature as [Watcher_loop.config.emit]. *)
  delete_branch_on_done : bool;
  agent_invoke   : agent_invoke;
  verifier_run   : verifier_run;
  budget         : int;
    (** Initial budget for the entire version. *)
  tier           : [ `A | `B | `C ];
  file_path      : string option;
    (** v2 batch 4b: when [Some f], status-block writes happen on the
        version branch (after [Version.start_new]) so the working tree
        is clean at gap-step preflight. *)
}

type result =
  | Done of {
      tag       : string;
      tier_dist : Inline_blocks.tier_distribution;
    }
  | Rolled_back

(** [run ~cfg ~baseline_sha ~d ?cotype ()] drives one version end to
    end. Emits [version.start], [version.commit] (one per accepted
    property), [version.complete] / [version.complete_error] events
    through [cfg.emit]. *)
val run :
  cfg:config ->
  baseline_sha:string ->
  d:Characterization.t ->
  ?cotype:Cotype.t ->
  unit -> result
