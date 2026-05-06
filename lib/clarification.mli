(** [Clarification] — pure helpers for the ADR-010 clarification-
    append flow.

    The cotype binding (production) lives in [Cotype.append_clarification];
    this module exposes the pure splice + a cotype-agnostic seam
    [append_via] used by tests with [Cotype_stub].

    @invariant P1 — only `## k4k:clarification:<ts>` sections are
                    added; pre-existing bytes pass through verbatim.
    @invariant P12 — concurrency safety is delegated to the supplied
                     cotype implementation. *)

(** [timestamp_of_now ()] — UTC `YYYY-MM-DD-HHMMSS`. *)
val timestamp_of_now : unit -> string

(** [splice ~base_bytes ~timestamp ~questions] — append a fresh
    `## k4k:clarification:<ts>` section listing [questions]. *)
val splice :
  base_bytes:string -> timestamp:string -> questions:string list -> string

(** Mirror of [Cotype.open_result]. *)
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

(** [append_via ~ensure_init ~open_ ~save ~path ~questions] —
    splice + save via the supplied cotype seam. Reads bytes from
    [open_]'s [base_path] (NEVER re-reads FILE). On Conflict, raises
    [Error.K4k_error E_state_corrupt] with the conflict path. *)
val append_via :
  ensure_init:(file:string -> (unit, string) result) ->
  open_:(file:string -> (cotype_open_result, string) result) ->
  save:(file:string -> base_sha:string -> actor:string -> bytes:string ->
        (cotype_save_outcome, string) result) ->
  path:string ->
  questions:string list ->
  unit
