(** See [.ml]. *)

val default_per_call : int
(** The per-agent-call token cap. Set far above the expected ceiling
    of any well-formed prompt so the gate functions as a
    runaway-safety net, not a cost-control mechanism. *)
