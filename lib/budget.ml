(** [Budget] — single-source-of-truth for the per-agent-call token cap.

    Per the project directive (recorded in conversation 2026-05-23):
    *"let's forget about tokens and simply make sure we have k4k
    optimize for autonomy under unambiguous goals and absence of
    uncertainties"*. The budget gate exists as a runaway-safety net,
    not as a cost-control mechanism. We set it high enough that no
    well-formed formalize / gap-step / kb-regen prompt should ever
    hit it.

    A formalize round-trip on a small spec is ~10k tokens; a gap-step
    on a real property is up to ~50k tokens. [default_per_call] is
    set far above both. If you see [budget_exhausted] in
    [.k4k/log.jsonl], something is genuinely runaway — the right
    response is to investigate the prompt, not to bump this number.

    Future work (NOT a v2 blocker): make this overridable per project
    via [.k4k/config.json]'s [budget.per_call] key, so cost-conscious
    operators can re-introduce a cap once we have stable token
    expectations per purpose. *)

let default_per_call = 1_000_000
