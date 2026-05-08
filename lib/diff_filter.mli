(** [Diff_filter] — path-level allowlist for unified diffs before
    they reach [Git.apply_diff].

    Agent-supplied diffs may write to anywhere [git apply --index]
    accepts, including k4k's own operational state under [.k4k/].
    [git reset --hard HEAD] does NOT clean [.k4k/] (it is in
    [Git.is_ignorable_path]), so a single poisoned diff can
    permanently invalidate manifest / audit / log files, bypassing
    the determinism contract. The filter rejects forbidden paths
    BEFORE any FS write happens (audit-2026-05-08-axis2 H1).

    @invariant P14 — file ownership: agent diffs are confined to the
                     user's source tree on the version branch. *)

(** [target_paths diff] — destination paths the diff would write to,
    parsed from [+++ b/<path>] / [+++ <path>] header lines, with the
    [b/] prefix stripped. [+++ /dev/null] (deletion markers) and
    blank targets are filtered out. *)
val target_paths : string -> string list

(** [is_forbidden path] — true iff [path] is empty, absolute,
    contains a [..] segment, or starts with [.k4k/] or [.git/]. *)
val is_forbidden : string -> bool

(** [first_forbidden diff] returns the first target path that
    [is_forbidden] flags, or [None] when all targets are safe. *)
val first_forbidden : string -> string option
