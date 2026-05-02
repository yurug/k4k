(** [Subprocess] — fork/exec wrapper with output capture + wall-clock
    timeout. Replaces [Sys.command] (forbidden by code-style.md).

    Used by [Verifier_dune_ocaml] (and the SIGINT/T16 test path). *)

type result = {
  exit_code   : int;       (** Process exit code. -1 if [timed_out]. *)
  stdout      : string;
  stderr      : string;
  duration_ms : int;
  timed_out   : bool;
}

(** [run ~prog ~args ()] runs [prog] with [args]; captures stdout and
    stderr; enforces a wall-clock [timeout_s]; on expiry, sends [SIGTERM]
    then [SIGKILL] one second later.

    @param cwd Working directory to use for the child (default: cwd).
    @param env Environment for the child (default: parent's).
    @param timeout_s Wall-clock cap in seconds (default: 60).
    @raise Unix.Unix_error if [Unix.create_process_env] itself fails
                           (e.g. ENOENT on [prog]). *)
val run :
  ?env:string array ->
  ?cwd:string ->
  ?timeout_s:int ->
  prog:string ->
  args:string list ->
  unit -> result
