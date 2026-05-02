(** [Gap_prompt] — pure: compose the [prompts/gap-step.md] body for a
    given property + characterization. No I/O. *)

val compose :
  Property.t ->
  Characterization.t ->
  current_summary:string ->
  string
