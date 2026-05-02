(** [Tty_status] — single-line in-place TTY status renderer.

    This module formats and writes the step-4 status line described
    in [kb/spec/algorithms.md] (Q3.4). On a real TTY it uses CR+ANSI
    clear-line for in-place updates; on a non-TTY (pipe, redirect)
    it auto-disables, so [stdout] is undisturbed.

    Key design decisions: pure rendering separated from I/O; the
    [render] function is unit-testable, the [print] function is
    a thin wrapper over [output_string]; the ETA model is a sliding
    median of the last 10 gap-step durations.
*)

(** Sliding-median window for ETA estimation.

    @invariant P11 — the renderer never writes secrets (input strings
                     pass through {!Logger.scrub} at the boundary). *)
type window

(** [empty_window ()] — a fresh window with no samples. *)
val empty_window : unit -> window

(** [push_duration w secs] — append [secs] to [w], dropping the oldest
    sample if the window is at capacity (10 samples). Pure update. *)
val push_duration : window -> float -> window

(** [median w] — the median of [w]'s samples. Returns [None] for the
    empty window. *)
val median : window -> float option

(** [eta_of w ~remaining] — estimated time to convergence in seconds.
    [None] when no samples yet. *)
val eta_of : window -> remaining:int -> float option

(** [format_eta secs] — human-readable [m:s] e.g. ["4m12s"]. *)
val format_eta : float -> string

(** [render ~step ~total ~property_id ~slug ~progress ~eta] —
    pure, returns the bytes that should be written to a real TTY.
    Format example:
      [k4k] step 3/12 • P3a4b1 (slug) • agent ####____ • ETA 4m12s

    @param progress Integer in [0..8]; bar of 8 cells. *)
val render :
  step:int ->
  total:int ->
  property_id:string ->
  slug:string ->
  progress:int ->
  eta:float option ->
  string

(** [is_tty ()] — true iff [Unix.isatty Unix.stdout]. *)
val is_tty : unit -> bool

(** [set_color_enabled b] — globally toggle ANSI escape emission.
    Defaults to [true]; [bin/main.ml] flips to [false] when the user
    passes [--no-color]. When disabled, {!print_inplace} degrades to
    a plain newline-terminated line (no CR, no clear-line escape). *)
val set_color_enabled : bool -> unit

(** [print_inplace s] — write [\r] + clear-line + [s] to stdout
    without a trailing newline (when ANSI is enabled); only call if
    {!is_tty} is true. With [--no-color], emits [s ^ "\n"] instead. *)
val print_inplace : string -> unit

(** [print_final_newline ()] — emit a single ['\n'] to terminate the
    status line before subsequent stdout writes. *)
val print_final_newline : unit -> unit
