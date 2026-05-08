(** [Status_splice] — pure: replace an existing [## k4k:status] block
    in an interaction-file body with a freshly-rendered one, or append
    if none exists. Used by the watcher's status-update path; cotype
    handles the concurrency separately.

    @invariant P1 — only [## k4k:status] (and trailing whitespace
                    around it) is mutated; all other sections pass
                    through byte-for-byte. *)

val replace_or_append : string -> string -> string
