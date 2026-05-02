(** [Coverage] — class-keyed coverage-checklist enforcement on [D].

    Per [kb/spec/data-model.md#coverage-checklists]. v0 ships only the
    [cli] checklist. Each missing aspect produces one [Error.issue]. *)

(** [check c] — returns the list of unmet coverage requirements; empty
    means stable.

    @invariant P2 — coverage failure ⇒ unstable. *)
val check : Characterization.t -> Error.issue list
