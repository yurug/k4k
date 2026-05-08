(** [Tradeoff_flow] — Tier-A→B/C tradeoff proposal authoring + sign-off
    polling (ADR-011 §5).

    @invariant P21 — proposals are only ever raised AFTER ≥1 Tier-A
                     attempt (the [Gap_step.Tradeoff] outcome already
                     gates this).
    @invariant P1  — every interaction-file mutation flows through
                     [Cotype.save]. *)

type proposal = {
  property_id    : string;
  why_a_failed   : string;
  proposed_tier  : [ `B | `C ];
  whats_lost     : string;
  whats_gained   : string;
}

type resolution =
  | Approved of [ `B | `C ]
  | Rejected of string
  | Timed_out

(** [propose_and_wait ~cotype ~file_path ~k4k_dir ~version_n ~emit
    ~proposal] splices a fresh `## k4k:tradeoff:proposal:<ts>` block
    into [file_path] via cotype, then polls cotype until the
    proposal's [Approval:] line resolves. On resolution the proposal
    block is archived to
    [.k4k/version/<version_n>/tradeoffs/<ts>.md] and replaced in
    [file_path] with a one-line HTML-comment breadcrumb. *)
val propose_and_wait :
  cotype:Cotype.t ->
  file_path:string ->
  k4k_dir:string ->
  version_n:int ->
  emit:(string -> Yojson.Safe.t -> unit) ->
  proposal:proposal ->
  resolution
