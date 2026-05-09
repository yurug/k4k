(** [Property] — runtime [Property] record per
    [kb/spec/data-model.md#property] and the pure derivation helpers
    (gap construction, risk score) per [algorithms.md#gap-construction]
    and [algorithms.md#risk-score].

    This module is responsible for:
    - the in-memory shape of a [Property];
    - [risk_score] (deterministic, no agent input — P17);
    - [argmax_lex] (stable selection — lexicographic tie-break on [id]);
    - [from_characterization] (gap construction).

    Persistence is the responsibility of [Persist]; serialization lives
    in [Property_json]. *)

(** Status enum, mirroring [data-model.md#property]. *)
type status =
  [ `Required | `Established | `Contradicted | `Unknown ]

(** Reference to a persisted artefact (see [agent-runs/], [verifier-runs/]). *)
type artefact_kind = [ `Agent_run | `Verifier_run ]

type artefact_ref = {
  kind : artefact_kind;
  ref_id : string;
}

type aspect_ref = {
  aspect : string;
  path   : string list;
}

type t = {
  id            : string;
  statement     : string;
  status        : status;
  evidence      : artefact_ref list;
  risk_score    : float;
  failure_count : int;
  last_failure_reason : string option;
  (** Set by [bump_failure] to the most recent reason string from
      [Gap_step.bump_and_classify] (e.g. "no diff in response",
      "verifier did not establish the focus property", "diff did
      not apply: <details>"). [Gap_prompt.compose] reads it back
      into the next prompt under a "Previous attempt" section so
      the agent learns from the prior failure rather than retrying
      blind. v2 batch 26 (Ralph-loop step 1). *)
  source        : aspect_ref;
}
(** v2 batch 11 (audit-axis5 M1): the prior [blocked : bool] field
    was a redundant mirror of [failure_count >= 3]. Dropped — the
    only meaningful 3-strike state is "tradeoff awaited", and that
    is signalled at the [Gap_step.outcome] / [Tradeoff_flow] level,
    not by stuffing a flag into the property record. *)

(** [risk_score p] = severity * uncertainty * blast_radius per
    [algorithms.md#risk-score]. Pure; no agent input.

    @invariant P17 — value derived from [p] alone (no agent judgment). *)
val risk_score : t -> float

(** [regen_risk p] returns [p] with [risk_score] recomputed. *)
val regen_risk : t -> t

(** [argmax_lex ps] selects the property with the highest [risk_score];
    lexicographic order of [id] breaks ties.

    @return [Some p] or [None] when [ps] is empty.
    @invariant P17 — selection is deterministic over inputs. *)
val argmax_lex : t list -> t option

(** [bump_failure ?reason p] increments [failure_count] and, if
    [reason] is given, records it on [last_failure_reason]. Reaching
    3 is the "three-strikes" signal that [Gap_step] turns into a
    [Tradeoff] outcome.

    @invariant P6 — three-strikes-then-tradeoff. *)
val bump_failure : ?reason:string -> t -> t

(** [with_status p st] sets [p.status] to [st] and zeroes the cached
    risk score (caller usually follows with [regen_risk]). *)
val with_status : t -> status -> t

(** [from_characterization d] enumerates one [Property] per aspect entry
    derived from [d]; each gets a stable id via [Property_id.of_path],
    a default [status = `Required], and a freshly computed [risk_score].

    @invariant P4 — IDs are part of the canonical AST and must be
                    stable across runs (deterministic on canonical D). *)
val from_characterization : Characterization.t -> t list

(** [make ~source ~statement ()] builds a property with a stable id and
    a freshly computed [risk_score]. *)
val make :
  source:aspect_ref ->
  statement:string ->
  ?status:status ->
  ?evidence:artefact_ref list ->
  ?failure_count:int ->
  ?last_failure_reason:string option ->
  unit -> t

(** [statement_of_aspect d a] derives a one-sentence claim from an
    aspect path. Pure. *)
val statement_of_aspect : Characterization.t -> aspect_ref -> string

(** [aspect_paths_of d] lists every aspect path derived from [d]. *)
val aspect_paths_of : Characterization.t -> aspect_ref list
