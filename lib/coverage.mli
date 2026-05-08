(** [Coverage] — class-keyed coverage-checklist enforcement on [D].

    Per [kb/spec/data-model.md#coverage-checklists]. v0 ships only the
    [cli] checklist. Each missing aspect produces one [Error.issue]. *)

(** [check c] — returns the list of unmet coverage requirements; empty
    means stable.

    @invariant P2 — coverage failure ⇒ unstable. *)
val check : Characterization.t -> Error.issue list

(** [conflicting_accept_pairs xs] — pairs of acceptance examples
    whose [(argv, stdin)] collide but whose [expect] outputs differ.
    Surfaces T2 ("conflicting acceptance examples"). Returns each
    conflict pair once, by example name.

    @invariant P2 — every detected pair becomes a coverage issue. *)
val conflicting_accept_pairs :
  Characterization.acceptance_example list ->
  (string * string) list
