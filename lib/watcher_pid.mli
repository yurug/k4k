(** [Watcher_pid] — single-instance enforcement via [.k4k/watcher.pid].

    ADR-011 §2: at most one watcher per file. The PID file holds the
    PID of the running watcher; on graceful exit it is removed; on
    crash it is stale and cleaned up by the next launch.

    [acquire] returns [Ok ()] when we own the PID file (any previously
    stale entry is reclaimed) or [Error pid] when another live watcher
    holds it — caller must abort with exit 5. *)

(** [pid_path k4k_dir] = [<k4k_dir>/watcher.pid]. *)
val pid_path : string -> string

(** [acquire ~k4k_dir] — write our PID. Returns [Error pid] if a live
    watcher already owns the file. Stale PIDs are reclaimed. *)
val acquire : k4k_dir:string -> (unit, int) result

(** [release ~k4k_dir] — remove the PID file (idempotent). *)
val release : k4k_dir:string -> unit

(** [pid_alive p] — true iff the OS reports PID [p] as a running
    process. *)
val pid_alive : int -> bool
