(** [Persist_lock] — P12 file-locking discipline for writes to
    [<file.k4k>].

    [kb/spec/config-and-formats.md] and
    [kb/properties/functional.md#P12] mandate an advisory exclusive
    lock around any write to the user-owned interaction file. The
    lock is held for the duration of the write only and released
    before any agent or verifier call.

    @invariant P12 — concurrent writers serialise through [flock]
                     ([Unix.lockf F_LOCK]); the lock is never held
                     across an agent or verifier invocation. *)

(** [with_exclusive_lock ~path k] runs [k ()] under an exclusive
    advisory lock on [path]. The lock is acquired by opening [path]
    read-write and calling [Unix.lockf F_LOCK 0]; it is released
    before this function returns (whether [k] returned or raised).
    [path] is created (touched) if it does not yet exist. *)
val with_exclusive_lock : path:string -> (unit -> 'a) -> 'a

(** [append_clarification ~path text] appends [text] to [<file.k4k>]
    under [with_exclusive_lock]. Concurrent callers serialise.

    @invariant P12. *)
val append_clarification : path:string -> string -> unit
