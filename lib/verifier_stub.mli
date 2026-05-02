(** [Verifier_stub] — deterministic in-memory verifier for tests.

    This module is responsible for satisfying [Verifier.S] without invoking
    a real toolchain. It implements P15.

    Step 1 only: [run] returns an empty [by_property] list with exit code 0.
*)

type t
type config = unit

val name : string
val version : t -> string
val create : config -> t

(** @invariant P15. *)
val run : t -> workdir:string -> focus:string list -> Verifier.run_result
