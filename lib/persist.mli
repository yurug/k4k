(** [Persist] — atomic file I/O for [.k4k/].

    This module is responsible for every state-changing write under the
    [.k4k/] tree. It implements P10 (atomic writes) and P12 (file locking).

    Key design decisions: every write goes [tmp]→fsync→rename→fsync(parent);
    a crash-injection hook between write and rename supports the P10 test;
    [.k4k/log.jsonl] is append-only (not via the atomic-write path).
*)

(** A pluggable hook fired between [tmp] write+fsync and [rename]. Used by
    the P10 test to simulate a crash. *)
type crash_hook = unit -> unit

(** [no_crash] is the production hook (does nothing). *)
val no_crash : crash_hook

(** [atomic_write ?crash_hook ~path content] writes [content] to [path]
    atomically. Pattern: open [path.tmp], write+fsync, run [crash_hook] (if
    any), close, rename, fsync the parent directory.

    @param path Absolute or working-dir-relative path; parent must exist.
    @param crash_hook Optional pre-rename hook for crash testing.
    @raise Error.K4k_error E_disk_full on [ENOSPC].
    @invariant P10 — partial state never persists past a crash. *)
val atomic_write : ?crash_hook:crash_hook -> path:string -> string -> unit

(** [append_jsonl_line ~path ~line] appends [line] + ['\n'] to [path],
    creating the file (and its parent directory) if necessary. JSONL is
    append-only, not atomic per-line.

    @raise Error.K4k_error E_disk_full on [ENOSPC]. *)
val append_jsonl_line : path:string -> line:string -> unit

(** [ensure_dir path] creates [path] (and any missing parents). Idempotent.

    @raise Error.K4k_error E_disk_full on [ENOSPC]. *)
val ensure_dir : string -> unit

(** [read_file path] reads the entire file as a byte string.

    @raise Error.K4k_error E_file_not_found if [path] is missing.
    @raise Error.K4k_error E_file_too_large if size > 10 MiB. *)
val read_file : string -> string

(** [file_size path] returns the file size in bytes.

    @raise Error.K4k_error E_file_not_found. *)
val file_size : string -> int

(** [sha256_hex bytes] is the lower-case hex SHA-256 of [bytes]. *)
val sha256_hex : string -> string

(** Maximum interaction-file size in bytes, per [config-and-formats.md]. *)
val max_interaction_file_bytes : int
