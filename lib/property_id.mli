(** [Property_id] — deterministic, length-prefixed hash of an aspect
    path per [kb/spec/algorithms.md#property-ids].

    The ID is stable across runs as long as the aspect's path is
    unchanged. Step 2 only generates the ID; gap construction (step 3)
    consumes it. *)

(** [of_path ["errors"; "EBADARG"; "when"]] returns ["P" ^ first7hex of
    sha256 of length-prefixed encoding].

    @invariant P4 — Property IDs are deterministic on the canonical
                    aspect path; equal paths yield equal IDs across
                    runs. *)
val of_path : string list -> string

(** Internal length-prefixed encoding; exposed for tests. *)
val encode_path : string list -> string
