(** [Cotype] — wrapper around the `cotype` CLI (PyPI: `cotype`).

    Per ADR-010, k4k delegates user-agent interaction-file concurrency
    to cotype. This module is the single shell-out boundary; downstream
    callers MUST go through it.

    @invariant P1 — every k4k-side mutation of the interaction file
                    flows through [save], which reads the prior bytes
                    from [open_]'s [base_path] (never from FILE).
    @invariant P12 — concurrency safety on the interaction file is
                     realized by cotype's sidecar lock, accessed via
                     [save]. k4k carries no [flock] code itself. *)

type config = { binary : string }

(** [default_config] → cotype binary on [$PATH]. *)
val default_config : config

type t

val name : string
(** "cotype" — used in the manifest [agent_backend.name] / log fields. *)

val create : config -> t

val version : t -> string
(** [version t] — the cotype binary's version string (parsed from
    [cotype --version]). Cached after the first call. Raises
    [Error.K4k_error E_agent_unavailable] if cotype is not on PATH. *)

type open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

(** [init t ~file] — `cotype init FILE --json`. Idempotent. *)
val init : t -> file:string -> (unit, string) result

(** [ensure_init t ~file] — alias of [init]; init is itself idempotent. *)
val ensure_init : t -> file:string -> (unit, string) result

(** [open_ t ~file] — capture a base snapshot. Returns the [base_sha]
    and a path to a frozen base copy the caller MUST read from
    (never re-read FILE directly). *)
val open_ : t -> file:string -> (open_result, string) result

type save_outcome =
  | Direct   of string                       (* sha *)
  | Merged   of string                       (* sha *)
  | Noop                                     (* equal to base *)
  | Conflict of { conflict_path : string }

(** [save t ~file ~base_sha ~actor ~bytes] — feed [bytes] via stdin to
    `cotype save FILE --base-sha <sha> --actor <actor>`. The [actor]
    label is opaque (record-only); k4k passes ["agent:k4k"]. *)
val save : t -> file:string -> base_sha:string -> actor:string ->
           bytes:string -> (save_outcome, string) result

(** [status t ~file] — `cotype status FILE --json`. *)
val status : t -> file:string ->
             ([ `Unmanaged | `Clean | `Conflicted ], string) result

(** [read_base t ~file] — convenience: ensure_init, open, then read
    the bytes from [base_path]. Enforces the load-bearing rule: never
    read FILE directly. Raises [Error.K4k_error] on failure. *)
val read_base : t -> file:string -> string

(** [append_clarification t ~path ~questions] — splice and save a
    fresh `## k4k:clarification:<ts>` section to [path]. Reads the
    existing bytes via [open_] (base_path), appends the new section,
    and saves via [save]. On conflict, raises
    [Error.K4k_error E_state_corrupt] with the conflict path.

    @invariant P1 — only `## k4k:clarification:*` sections are added.
    @invariant P12 — concurrency delegated to cotype's sidecar lock. *)
val append_clarification :
  t -> path:string -> questions:string list -> unit
