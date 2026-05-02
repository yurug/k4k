---
id: adr-007
type: decision
summary: v0 ships target-KB regeneration as a deterministic in-process renderer, not as agent calls. The agent path (per algorithms.md#kb-regen) is wired but inactive; activation is v1+.
domain: architecture
last-updated: 2026-05-02
depends-on: [adr-003, adr-006, spec.algorithms]
refines: [adr-006]
related: [conventions.context-economy, properties.functional]
---

# ADR-007: Deterministic in-process kb-regen for v0

## Status
Accepted (2026-05-02). Ships in v0 step 4.

## Context

`kb/spec/algorithms.md#kb-regen` describes target-KB regeneration as **one agent call per affected file**, using `prompts/kb-regen.md`. While implementing step 4 we faced a tactical choice:

1. **Agent-driven (per the spec)**: every successful gap-step costs N additional agent calls (one per KB file whose source-of-truth aspect changed). For the v0 6-file target KB (`INDEX.md`, `GLOSSARY.md`, `spec/data-model.md`, `spec/algorithms.md`, `properties/functional.md`, `properties/edge-cases.md`), a typical step touches 1–3 files, so 1–3 extra calls per step. At 1 000 budget units per invocation hard cap, this rapidly competes with gap-step calls themselves.
2. **Deterministic in-process renderer**: the harness composes the file body itself from the formal characterization (`D`) and the current verifier state (`S`). No agent, no token spend, fully reproducible.

Both options preserve the user-facing contract: target-KB files have valid frontmatter (`id`, `type`, `summary`, `domain`, `last-updated`, `owner: k4k`, `content_hash`), are regenerated only when the underlying aspect changed, and respect ownership-flips (P14, P16).

## Decision

v0 implements **option 2 — deterministic in-process rendering** in `lib/Kb_regen` (the rendering logic) and `lib/Kb_render` (the per-file body composers). The agent path is **wired but inactive**:
- `prompts/kb-regen.md` ships, embedded into the binary via `lib/Prompts.embedded`.
- The `Agent_backend` signature accepts `purpose = `Kb_regen`. `Backend_stub` and `Backend_claude` both honor it.
- `Kb_regen.regen` selects the renderer at runtime based on a configuration flag — currently always `` `Deterministic ``. A v1 switch flips this to `` `Agent_driven ``.

## Consequences

**v0 wins:**
- Zero token spend on KB regeneration.
- Bit-for-bit reproducibility — the same `(D, S)` always produces the same target-KB body, hash and all.
- No flake-class introduced by stochastic LLM output.
- No prompt-engineering surface to maintain in v0.

**v0 cost:**
- The deterministic renderer is human-authored (in OCaml). Adding a new target-KB file requires code changes plus `kb_source_map` updates — *not* just a prompt template.
- Renderer output is necessarily formulaic: it cannot synthesize prose the way a model would. For domain-style sections (`GLOSSARY` term explanations, narrative `domain/prd.md`-equivalents), the v0 output reads more like a reference card than a hand-written PRD.

**v1 transition:**
- Switching `Kb_regen.mode = `Agent_driven` makes the harness call `Agent_backend.invoke ~purpose:`Kb_regen` with the embedded `prompts/kb-regen.md`. The deterministic renderer becomes a fallback when `K4K_LIVE != "1"` and no `K4K_STUB_RESPONSES` are configured — keeping CI fast and offline.

## What this means for implementers

- **`lib/Kb_regen` is a switching dispatcher.** Today it only dispatches one direction. Do not assume the v0 implementation defines the contract — `algorithms.md#kb-regen` does.
- **The static `kb_source_map`** in `lib/Kb_regen` (file → list of aspects) is the v0 truth source. Future versions may compute it dynamically from prompt-template metadata.
- **Tests run against the deterministic path by default**, including the `S1_echo_first_run_e2e` integration test. This means S1's target-KB output is fully predictable — useful for snapshot-style assertions in Phase-5 audits.
- **Do not extend the deterministic renderer indefinitely.** If a new target-KB file requires substantive natural language (e.g. an architecture rationale), that is a signal to flip the v0 default and let the agent author it. The point of the deterministic path is "right by construction for structured content"; it is not a permanent escape from agent calls.

## Relationship to NOTES.md

The vision in `kb/NOTES.md` says the harness "never relies on the *judgment* of agents to validate". KB regeneration is *production*, not *validation* — it does not gate state transitions. So the agent-judgment prohibition does not bind here: any future agent-driven regeneration is fine, provided the *user* and the *characterization* remain authoritative for what the program is supposed to do.
