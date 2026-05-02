(** [Sigint] — cooperative SIGINT/SIGTERM handler with at_exit cleanup.

    Implements P8 / NF1: signal → exit ≤ 5 s. Cleanup of scratch git
    branches (Q3.2) is performed via [register_cleanup] +
    [Stdlib.at_exit]. *)

(** [install ()] — install the SIGINT/SIGTERM handler. Idempotent.
    @invariant P8 — the harness exits ≤ 5 s after a signal. *)
val install : unit -> unit

(** [should_exit ()] — true if a SIGINT/SIGTERM has been received.
    @invariant P8 — polled at safe points to bound exit latency. *)
val should_exit : unit -> bool

(** [reset_for_test ()] — clear the flag (test-only). *)
val reset_for_test : unit -> unit

(** [set_for_test ()] — set the flag (test-only). *)
val set_for_test : unit -> unit

(** [register_cleanup f] — register [f] both for [at_exit] and for
    invocation when the harness initiates a graceful exit. *)
val register_cleanup : (unit -> unit) -> unit

(** [raise_if_needed ()] — if a signal flag has been set, raise
    [E_state_corrupt "interrupted by signal"] for the harness to
    intercept. Called at safe points. *)
val raise_if_needed : unit -> unit
