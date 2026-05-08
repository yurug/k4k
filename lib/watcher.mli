(** [Watcher] — the v2 autonomous-agent main loop (ADR-011, ADR-013).

    Single foreground process per file, polling cotype at 2 Hz. Stdout
    emits structured JSONL state-transition events; stderr is empty at
    default verbosity. SIGINT/SIGTERM trigger cooperative shutdown ≤ 5 s
    (NF1, P8). PID-file enforces single-instance per file (ADR-011 §2).

    @invariant P1, P12 — every interaction-file mutation flows through
                          [Cotype.save] (via [Clarification] /
                          [Inline_blocks] renderers). *)

type config = {
  file_path        : string;
  k4k_dir          : string;
  verbosity        : [ `Quiet | `Verbose | `Debug ];
  exit_on_stable   : bool;
    (** [@test_only] When [true], the watcher returns after the first
        stability snapshot rather than entering the gap-step loop. Used
        by integration tests (per [kb/runbooks/test-environment.md]). *)
  exit_on_done     : bool;
    (** [@test_only] When [true], the watcher returns once a version
        completes (or rolls back). *)
  poll_interval_ms : int;
    (** Default 500 ms (2 Hz). Tests may shorten. *)
}

type startup_outcome =
  | Started
  | Already_running of int (** PID of the live watcher *)
  | Aborted of string

(** [startup ~config] performs ADR-011 §3 setup:
    - resolve the absolute file path
    - create starter template if file missing
    - insert minimal frontmatter via cotype save if missing
    - [git init] when not in a git work tree
    - acquire the PID file
    Returns [Already_running pid] if another live watcher owns the PID
    file; the caller exits 5. *)
val startup : config:config -> startup_outcome

(** [run ~config] enters the main loop. Polls cotype, snapshots
    versions on stable, runs gap-step, handles user directives. Exits
    cleanly on signal or [exit_on_stable]. Returns 0 on graceful
    shutdown; non-zero only if startup-phase invariants fail. *)
val run : config:config -> int
