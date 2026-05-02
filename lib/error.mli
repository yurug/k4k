(** [Error] — closed error taxonomy for k4k.

    This module is responsible for defining the closed set of errors k4k may
    emit, mapping them to exit codes and human-readable messages. It implements
    P7 (closed error taxonomy).

    Key design decisions: a single algebraic [error] type whose constructors
    map 1:1 to the entries in [kb/spec/error-taxonomy.md]; two exceptions —
    [K4k_error] for user-visible failures, [Invariant_violation] for
    code-internal panics (exit 64+). Mapping tables are pure functions.
*)

(** A structural issue found during stability checking. The [section]
    is the section id (or pseudo-id like ["frontmatter"]); [details] is a
    human-readable explanation; [line] is 1-based when available. *)
type issue = { section : string; line : int option; details : string }

(** Closed catalog of user-visible errors. Each constructor maps to one
    entry in [kb/spec/error-taxonomy.md]. *)
type error =
  | E_format               of { line : int; col : int; reason : string }
  | E_unstable             of issue list
  | E_version              of { found : int; supported : int list }
  | E_class_unsupported    of string
  | E_budget               of { used : int; cap : int }
  | E_max_steps            of int
  | E_agent_unavailable    of string
  | E_verifier_unavailable of string
  | E_verifier_tool_error  of string
  | E_disk_full            of string
  | E_state_corrupt        of string
  | E_encoding             of int
  | E_file_not_found       of string
  | E_file_too_large       of int

(** Raised for every user-visible failure. The wrapping
    [try ... with K4k_error e -> ...] lives in [bin/main.ml]. *)
exception K4k_error of error

(** Raised for internal invariant violations. Exit code 64+. *)
exception Invariant_violation of string

(** [code_id e] returns the canonical short identifier (e.g. ["EFORMAT"]).

    @return Always one of the IDs listed in [kb/spec/error-taxonomy.md].
    @invariant P7 — the catalog is closed. *)
val code_id : error -> string

(** [exit_code_of e] returns the exit code for [e].

    @return An integer in {0, 1, 2, 3, 4, 5, 64}; 64 reserved for
            the invariant-violation hand-off but never returned by
            this function (panics use a separate path).
    @invariant P7 — exit codes are documented in the taxonomy. *)
val exit_code_of : error -> int

(** [render e] builds the user-visible stderr line (no trailing newline,
    no [k4k:] prefix — that is added by [Logger]).

    @return One-line string suitable for the [k4k: <msg>] template. *)
val render : error -> string

(** [issue ?line ~section details] — convenience constructor. *)
val issue : ?line:int -> section:string -> string -> issue
