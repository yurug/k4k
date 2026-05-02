(** [Logger] — stderr text output and JSONL audit log.

    This module is responsible for emitting human-readable diagnostics on
    stderr and structured JSONL events to [.k4k/log.jsonl]. It implements
    P11 (stdout/stderr discipline) and the audit-log discipline.

    Key design decisions: stdout is reserved for protocol output (status
    line / [done] / [stable …]); diagnostics go to stderr only above the
    default verbosity level. The JSONL log is append-only via
    [Persist.append_jsonl_line]. Secret scrubbing runs over every line
    before write.
*)

(** Verbosity levels.
    - [`Quiet]: default — no stderr at all (P11).
    - [`Verbose]: [-v] — one line per state transition on stderr.
    - [`Debug]: [-vv] — also include subprocess details. *)
type verbosity = [ `Quiet | `Verbose | `Debug ]

(** Logger handle. Constructed once in [bin/main.ml] / tests. *)
type t

(** [create ~verbosity ~jsonl_path] builds a logger writing JSONL lines to
    [jsonl_path] (created if missing) and stderr lines per [verbosity].

    @param jsonl_path Optional path for the JSONL log; [None] disables it.
    @return A fresh logger.
    @invariant P11 — stdout is never touched by this module. *)
val create : verbosity:verbosity -> jsonl_path:string option -> t

(** [info t event details] — emit a structured INFO event.

    @param event The canonical event name (e.g. ["stability.start"]).
    @param details A pre-built JSON object (often [`Assoc []]).
    @invariant P11. *)
val info : t -> string -> Yojson.Safe.t -> unit

(** [warn t event details] — emit a structured WARN event. *)
val warn : t -> string -> Yojson.Safe.t -> unit

(** [error t err] — emit a structured ERROR event for a [K4k_error] value
    and (at any verbosity) write the matching [k4k: <msg>] line to stderr.

    @invariant P7 — uses [Error.code_id] and [Error.render]. *)
val error : t -> Error.error -> unit

(** [stdout_line t line] — write [line] (newline-terminated) to stdout.
    Used only by [Harness.run] for the final protocol output.

    @invariant P11. *)
val stdout_line : t -> string -> unit

(** [scrub s] redacts API key/token-shaped substrings.

    @return [s] with key=value-shaped patterns replaced by [<scrubbed>].
    @invariant NF5 (best-effort secrets quarantine; full canary test
                    in step 4). *)
val scrub : string -> string
