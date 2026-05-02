(** [Sigint] — cooperative SIGINT/SIGTERM handler.

    On installation, replaces the OCaml default (which raises
    [Sys.Break]) with a flag-set-and-poll model. The harness checks
    [should_exit ()] at safe points (between gap-steps and inside
    polling loops). Once the flag is set, the harness initiates
    cleanup (scratch-branch discipline) and exits ≤ 5 s after the
    signal (NF1).

    Multiple installations are idempotent. *)

let flag = Atomic.make false

let installed = ref false

let cleanups : (unit -> unit) list ref = ref []

let on_signal _ =
  Atomic.set flag true

let install () =
  if not !installed then begin
    installed := true;
    Sys.set_signal Sys.sigint (Sys.Signal_handle on_signal);
    (try Sys.set_signal Sys.sigterm (Sys.Signal_handle on_signal)
     with Invalid_argument _ -> ());
  end

let should_exit () = Atomic.get flag

let reset_for_test () =
  Atomic.set flag false

let set_for_test () =
  Atomic.set flag true

let safe f = try f () with _ -> ()

let register_cleanup f =
  cleanups := f :: !cleanups;
  Stdlib.at_exit (fun () -> safe f)

let raise_if_needed () =
  if Atomic.get flag then
    raise (Error.K4k_error (Error.E_state_corrupt
      "interrupted by signal"))
