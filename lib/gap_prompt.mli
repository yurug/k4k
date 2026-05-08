(** [Gap_prompt] — pure: compose the tier-aware gap-step prompt body
    for a given property + characterization (ADR-012). No I/O.

    [tier] defaults to [`A] (the v2 baseline per ADR-011 §4). [`B]
    / [`C] templates are loaded only after a user-signed tradeoff
    proposal records a degradation. *)

val compose :
  ?tier:[ `A | `B | `C ] ->
  Property.t ->
  Characterization.t ->
  current_summary:string ->
  string
