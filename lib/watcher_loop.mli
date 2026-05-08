(** [Watcher_loop] — the inner main loop body for [Watcher]. Polls
    cotype, runs stability, snapshots versions, drives the gap-step
    loop, handles user directives. *)

type config = {
  file_path        : string;
  k4k_dir          : string;
  verbosity        : [ `Quiet | `Verbose | `Debug ];
  exit_on_stable   : bool;
  poll_interval_ms : int;
  emit             : string -> Yojson.Safe.t -> unit;
}

(** [run config] enters the main loop. Returns 0 on graceful shutdown
    (SIGINT/SIGTERM or [exit_on_stable]); non-zero if a fatal startup
    invariant fails. *)
val run : config -> int
