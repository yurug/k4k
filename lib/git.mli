(** [Git] — minimal wrapper around [git] subprocess invocations used by
    [Gap_step] for scratch-branch discipline per Q3.2.

    All operations are stateless w.r.t. k4k: the user-supplied [cwd] is
    the only state. Each call returns [(unit, string) result] where the
    [Error] payload is git's stderr (trimmed). *)

(** [is_repo ~cwd] — true iff [cwd] is a git working tree. *)
val is_repo : cwd:string -> bool

(** [current_branch ~cwd] — current branch name, e.g. ["main"]. *)
val current_branch : cwd:string -> string

(** [is_clean ~cwd] — [(true, [])] when the working tree is clean;
    [(false, dirty_paths)] otherwise. Dirty paths come from
    [git status --porcelain], with [.k4k/] (k4k's own operational state),
    [_build/] (dune's build output), and [.<file>.cotype/] (cotype
    per-file sidecars, ADR-010) filtered out: all are universally
    regenerable, never part of the user's committed source, and always
    appear as untracked on first run regardless of the user's [.gitignore]. *)
val is_clean : cwd:string -> bool * string list

(** [branch_exists ~cwd ~name]. *)
val branch_exists : cwd:string -> name:string -> bool

(** [create_branch ~cwd ~name] = [git checkout -b <name>]. *)
val create_branch : cwd:string -> name:string -> (unit, string) result

(** [checkout ~cwd ~name] = [git checkout <name>]. *)
val checkout : cwd:string -> name:string -> (unit, string) result

(** [delete_branch ~cwd ~name] = [git branch -D <name>]. *)
val delete_branch : cwd:string -> name:string -> (unit, string) result

(** [apply_diff ~cwd ~diff] = [git apply --index] over a unified-diff
    string. The [--index] flag keeps working tree and index in sync. *)
val apply_diff : cwd:string -> diff:string -> (unit, string) result

(** [commit_all ~cwd ~message] stages all changes and commits with the
    given message; idempotent on a clean tree (allowed empty). *)
val commit_all :
  cwd:string -> message:string -> (unit, string) result

(** [merge_ff_only ~cwd ~name] = [git merge --ff-only <name>]. *)
val merge_ff_only : cwd:string -> name:string -> (unit, string) result

(** [init ~cwd] — initialize a fresh repo at [cwd] on branch [main].

    [@test_only] The production harness expects the user to have
    initialised the project repo themselves; only the unit and
    integration tests use this helper to bootstrap a scratch repo. *)
val init : cwd:string -> (unit, string) result

(** [configure_test_identity ~cwd] sets a deterministic
    [user.name] / [user.email] in [cwd] so [git commit] does not fail
    on a CI runner with no global git identity.

    [@test_only] As above, this is exported for the unit and
    integration tests, not for the production harness — k4k never
    edits the user's git config. *)
val configure_test_identity : cwd:string -> unit

(** [scratch_branch_name ~property_id] — Q3.2 naming
    [k4k/gap/<property-id>/<YYYYMMDD-HHMMSS-rand>]. *)
val scratch_branch_name : property_id:string -> string
