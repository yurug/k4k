(** [Version_user_edits] — P22: detect user edits to the [.k4k] file
    during a version's gap-step loop, queue them for the next version,
    surface the count in the status block, and commit the residue on
    the version branch so [Gap_step.preflight] can proceed.

    @invariant P22 — user edits to user-owned sections during the
                     [developing] state never interrupt the in-flight
                     gap-step loop. They are committed on the version
                     branch (and therefore merge to [main] on
                     completion); the watcher's next stability tick
                     formalizes the new spec and starts version N+1.

    @invariant P14 — k4k commits user-owned content here without
                     mutating it. The commit is bookkeeping; the
                     bytes the user wrote land verbatim in the merge. *)

type cfg = {
  cwd       : string;
  emit      : string -> Yojson.Safe.t -> unit;
  file_path : string option;
}

(** [splice_status_block ~cotype ~file_path ~status_block] — replace
    the existing [## k4k:status] block in [file_path] (or append if
    none) via cotype. Idempotent on the bytes; failures are
    swallowed (the caller's contract is best-effort UI surface). *)
val splice_status_block :
  cotype:Cotype.t ->
  file_path:string ->
  status_block:string ->
  unit

(** Snapshot the user-section hashes of the file at [file_path] (via
    cotype). Returns [[]] when cotype is unavailable, [file_path] is
    [None], the file is unreadable, or parsing fails. *)
val snapshot :
  ?cotype:Cotype.t ->
  file_path:string option ->
  unit ->
  (string * string) list

(** [count_drift ~baseline_hashes ~current_hashes] — number of
    user-owned sections present in [baseline_hashes] whose hash
    differs in [current_hashes] (or is absent). *)
val count_drift :
  baseline_hashes:(string * string) list ->
  current_hashes:(string * string) list ->
  int

(** [check_and_queue ~cfg ~v_number ~baseline ~surfaced ?cotype ()]

    Re-read the file via cotype, count drift vs [baseline] (the
    snapshot taken at version start), and — only when the new count
    differs from [!surfaced] (i.e. fresh user activity since the last
    iteration):
    - splice an updated [## k4k:status] block carrying the new
      [pending_user_edits] count;
    - commit the working tree (user's edits + status splice) on the
      version branch with message
      [\[k4k\] queue user edits for v<v_number+1> (N section(s))];
    - emit a ["user_edits.queued"] JSONL event;
    - update [surfaced] to the new count.

    Returns the drift count. The [surfaced] ref deduplicates: the
    same [n] across consecutive iterations is surfaced exactly once,
    so a single mid-flight user edit produces one [user_edits.queued]
    event and one commit, regardless of how many properties the gap
    loop iterates afterwards. *)
val check_and_queue :
  cfg:cfg ->
  v_number:int ->
  baseline:(string * string) list ->
  surfaced:int ref ->
  ?cotype:Cotype.t ->
  unit ->
  int
