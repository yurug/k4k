(** [Stability] — structural stability of an interaction file.

    This module is responsible for the structural half of the
    stability check (P2 sub-clause). It implements P3 (binary verdict).

    Key design decisions: pass/fail only — no scores; the semantic stage
    is stubbed to ["Stable"] in step 1; rules: every required user-section
    must be present, non-empty, and trimmed.
*)

(** A binary stability verdict. *)
type t =
  | Stable
  | Unstable of Error.issue list

(** [check_structural file] returns [Stable] iff [file] passes the
    structural rules:
    - every id in [Parser.required_user_section_ids] is present;
    - every required section's [content] is non-empty when trimmed.
    Otherwise returns [Unstable issues] with one issue per missing or
    empty section.

    @invariant P3 — pass/fail only.
    @invariant P2 — partial implementation: structural stage. *)
val check_structural : Parser.interaction_file -> t

(** [check_semantic file] is the semantic stub for step 1 — always
    returns [Stable]. The real check lands in step 2.

    @invariant P3. *)
val check_semantic : Parser.interaction_file -> t

(** [is_stable t] — convenience predicate. *)
val is_stable : t -> bool
