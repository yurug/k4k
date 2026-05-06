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

(** [trace_write_path path] — when [K4K_TEST_TRACE_WRITES=<file>] is
    set, append [path] to that file (one path per line). Production
    runs leave the env unset and this is a no-op. Exposed so writers
    outside this module ([Persist_lock]) can participate in the NF4
    envelope trace. *)
val trace_write_path : string -> unit

(** [atomic_write ?crash_hook ~path content] writes [content] to [path]
    atomically. Pattern: open [path.tmp], write+fsync, run [crash_hook] (if
    any), close, rename, fsync the parent directory.

    Test-only: when [K4K_TEST_TRACE_WRITES=<file>] is set, every call
    appends [path] to [<file>]. Production runs leave the env var unset
    and the trace path is never created. Used by the
    [NF4_state_confinement_envelope] test.

    @param path Absolute or working-dir-relative path; parent must exist.
    @param crash_hook Optional pre-rename hook for crash testing.
    @raise Error.K4k_error E_disk_full on [ENOSPC].
    @invariant P10 — partial state never persists past a crash.
    @invariant P12 — write-only; the lock-discipline is enforced at
                     the call boundary in [Harness] (no lock held
                     across agent calls).
    @invariant NF4 — every write goes via this function, so the trace
                     hook captures the full envelope. *)
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

(** [agent_run_id ()] — a fresh, monotonic, unique-enough id for an
    agent-run directory. Format
    [YYYYMMDD-HHMMSS-XXXXXX] (UTC, hex random). The optional [now] and
    [rand] parameters exist for testability. *)
val agent_run_id :
  ?now:(unit -> float) ->
  ?rand:(unit -> int) ->
  unit -> string

(** [write_desired ~k4k_dir ~bytes ~mirror_md] — atomic write of
    [.k4k/characterization/desired/spec.json] (canonical JSON) and a
    human-readable mirror [.k4k/characterization/desired/spec.md] (with
    [owner: k4k] frontmatter).

    @invariant P10 — atomic. *)
val write_desired :
  k4k_dir:string -> bytes:string -> mirror_md:string -> unit

(** [write_agent_run ~k4k_dir ~run_id ~prompt ~response ~verdict] —
    persist a single agent-run's artefacts under
    [.k4k/agent-runs/<run_id>/]. *)
val write_agent_run :
  k4k_dir:string ->
  run_id:string ->
  prompt:string ->
  response:string ->
  verdict:string ->
  unit

(** [write_divergence_report ~k4k_dir ~run_id ~report] — persist a
    divergence-report JSON next to the offending agent-run. *)
val write_divergence_report :
  k4k_dir:string -> run_id:string -> report:string -> unit

(** [gap_path k4k_dir] = ".k4k/gap/properties.json". *)
val gap_path : string -> string

(** [write_gap ~k4k_dir ~bytes] atomically writes the gap-property file.

    @invariant P10 — atomic. *)
val write_gap : k4k_dir:string -> bytes:string -> unit

(** [read_gap ~k4k_dir] returns the file's bytes if it exists. *)
val read_gap : k4k_dir:string -> string option

(** [write_verifier_run ~k4k_dir ~run_id ~stdout ~stderr ~result] —
    persist a single verifier-run's artefacts under
    [.k4k/verifier-runs/<run_id>/]. *)
val write_verifier_run :
  k4k_dir:string ->
  run_id:string ->
  stdout:string ->
  stderr:string ->
  result:string ->
  unit

(** {1 Clarification append (post-ADR-010, via cotype)}

    Per ADR-010, every k4k mutation of the interaction file flows
    through cotype: open → splice → save. This module exposes a
    cotype-agnostic seam ([append_clarification_via]) for tests, plus
    a thin convenience binding to [Cotype] for production. *)

(** Mirror of [Cotype.open_result] — kept here so callers don't need
    to depend on [Cotype] directly. *)
type cotype_open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

(** Mirror of [Cotype.save_outcome]. *)
type cotype_save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

(** [append_clarification_via ~ensure_init ~open_ ~save ~path
    ~questions] — splice-and-save a fresh `## k4k:clarification:<ts>`
    section to [path] via the supplied cotype seam. The base bytes
    are always read from [open_]'s [base_path] (never from FILE
    directly), per ADR-010.

    Conflict outcomes raise [Error.K4k_error E_state_corrupt] with
    the conflict path embedded.

    @invariant P1 — only `## k4k:clarification:*` sections are added;
                   pre-existing sections flow through byte-for-byte.
    @invariant P12 — concurrency is delegated to cotype's sidecar lock. *)
val append_clarification_via :
  ensure_init:(file:string -> (unit, string) result) ->
  open_:(file:string -> (cotype_open_result, string) result) ->
  save:(file:string -> base_sha:string -> actor:string -> bytes:string ->
        (cotype_save_outcome, string) result) ->
  path:string ->
  questions:string list ->
  unit

(** [append_clarification ~cotype ~path ~questions] — production
    binding of [append_clarification_via] to a live [Cotype.t]. *)
val append_clarification :
  cotype:Cotype.t -> path:string -> questions:string list -> unit

(** [splice_clarification ~base_bytes ~timestamp ~questions] —
    pure helper: produce the proposed bytes by appending a fresh
    `## k4k:clarification:<timestamp>` section to [base_bytes]. *)
val splice_clarification :
  base_bytes:string -> timestamp:string -> questions:string list -> string

(** [timestamp_of_now ()] — UTC `YYYY-MM-DD-HHMMSS` for use in
    `## k4k:clarification:<ts>` headings. *)
val timestamp_of_now : unit -> string
