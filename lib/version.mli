(** [Version] — the per-version state machine and git-branch lifecycle
    for autonomous-agent v2 (ADR-011 §6, ADR-013 §2).

    A [Version.t] tracks one in-flight or completed development cycle.
    Each version is a git branch [k4k/version/<n>] cut from the user's
    default branch; on completion k4k merges back and tags [v<n>].
    Audit-only metadata (the JSON serialization of [t]) lives at
    [.k4k/version/<n>/manifest.json] per ADR-013 §3.

    All git side effects go through [Git]; this module owns no shell
    invocations of its own. *)

(** ADR-011 §6: the version states. The state machine:

    {v
    Drafting → Refining ⇄ Stable → Developing → [Awaiting_tradeoff]
                  ↑               ↓                       ↓
                  └── Paused_unknown ←─────────────────────┘
                  └── Rolled_back / Done
    v} *)
type state =
  | Drafting
  | Refining
  | Stable
  | Developing
  | Awaiting_tradeoff
  | Paused_unknown
  | Done
  | Rolled_back

(** ADR-013 §3 manifest fields. *)
type t = {
  number           : int;
  state            : state;
  baseline_sha     : string;
  branch_name      : string;
  d_hash           : string;
  started_at       : float;
  tier_assignments : (string * [ `A | `B | `C ]) list;
}

(** [branch_name_of n] = ["k4k/version/<n>"]. *)
val branch_name_of : int -> string

(** [tag_name_of n] = ["v<n>"]. *)
val tag_name_of : int -> string

(** [start_new ~cwd ~number ~baseline_sha ~d_hash] cuts
    [k4k/version/<number>] from the current default-branch [HEAD] and
    checks it out. The caller persists the returned record to
    [.k4k/version/<n>/manifest.json] via [to_yojson].

    Returns [Error] if [k4k/version/<n>] already exists (caller should
    treat that as [E_state_corrupt] per ADR-013 §2: collisions are not
    expected in practice). *)
val start_new :
  cwd:string ->
  number:int ->
  baseline_sha:string ->
  d_hash:string ->
  (t, string) result

(** [commit_accept ~cwd ~property_id ~message] does [git add -A] then
    [git commit -m <message>] on the in-flight branch (caller is
    expected to be on it). Returns the new HEAD sha on success.
    ADR-013 §2 step 3: messages take the [\[k4k\] establish <pid>] form. *)
val commit_accept :
  cwd:string ->
  property_id:string ->
  message:string ->
  (string, string) result

(** [complete ~cwd t ~default_branch] checks out [default_branch],
    runs [Git.merge ~name:t.branch_name] (fast-forward when possible,
    no-fast-forward fallback with a [\[k4k\] merge version <n>] message),
    annotates a [v<n>] tag at the merge point, and (configurable)
    deletes [t.branch_name]. Returns the tag name on success.
    ADR-013 §2 step 5. *)
val complete :
  cwd:string ->
  t ->
  default_branch:string ->
  ?delete_branch:bool ->
  unit ->
  (string, string) result

(** [rollback ~cwd t ~default_branch] checks out [default_branch]
    (idempotent if already there), then deletes [t.branch_name] via
    [git branch -D]. ADR-013 §2 step 6. *)
val rollback :
  cwd:string ->
  t ->
  default_branch:string ->
  (unit, string) result

(** [current_default_branch ~cwd] thin wrapper over
    [Git.default_branch ~cwd]. *)
val current_default_branch : cwd:string -> string

(** [to_yojson t] / [of_yojson v] — JSON codec used by the persist path
    for [.k4k/version/<n>/manifest.json]. *)
val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> t
