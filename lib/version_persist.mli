(** [Version_persist] — filesystem I/O helpers for the per-version
    audit-only directory at [.k4k/version/<n>/] (ADR-013 §3).

    Disk-only; no git. Companion to [Version] (which owns the git
    side effects) and [Version_loop] (which owns the orchestration). *)

val dir_for           : k4k_dir:string -> number:int -> string
val manifest_path     : k4k_dir:string -> number:int -> string
val d_spec_path       : k4k_dir:string -> number:int -> string
val tiers_path        : k4k_dir:string -> number:int -> string
val audit_path        : k4k_dir:string -> number:int -> string
val agent_runs_dir    : k4k_dir:string -> number:int -> string
val clarifications_dir: k4k_dir:string -> number:int -> string
val tradeoffs_dir     : k4k_dir:string -> number:int -> string

val ensure_dirs : k4k_dir:string -> number:int -> unit

(** Persist [.k4k/version/<n>/manifest.json] capturing
    tool versions, the [Version.t] record, and (optionally) the tag. *)
val write_manifest :
  k4k_dir:string ->
  v:Version.t ->
  ?tag_name:string ->
  ?cotype_version:string ->
  ?agent_name:string ->
  ?agent_version:string ->
  ?verifier_name:string ->
  ?verifier_version:string ->
  unit -> unit

(** Persist the canonical desired characterization at
    [.k4k/version/<n>/D-spec.json] (ADR-005 canonical AST snapshot). *)
val write_d_spec :
  k4k_dir:string -> number:int -> d:Characterization.t -> unit

(** Persist [.k4k/version/<n>/tiers.json] with per-property tier
    assignments. *)
val write_tiers :
  k4k_dir:string -> number:int ->
  tiers:(string * [ `A | `B | `C ]) list -> unit

(** Persist a pre-rendered audit.md to [.k4k/version/<n>/audit.md]. *)
val write_audit : k4k_dir:string -> number:int -> content:string -> unit

(** Highest existing [.k4k/version/<n>/] number plus one; 1 on a
    fresh project. *)
val next_version_number : k4k_dir:string -> int
