---
id: adr-020
type: decision
summary: The agent proof backend follows a METHODOLOGY instead of one-shot monolithic generation. Four phases — implement-naive, sketch (a kernel-checked proof skeleton with the lemmas Admitted), fill (prove each lemma in isolation, focused feedback), assemble (final coqc gate, no admits). The keystone is the SKELETON GATE: coqc checks the decomposition is type-correct and sufficient before any lemma is proved. Correctness-only for v1; naive→efficient refinement deferred.
domain: architecture
last-updated: 2026-06-20
depends-on: [adr-019, adr-016, conventions.context-economy, glossary]
refines: [adr-019]
related: [adr-013, notes]
---

# ADR-020: Structured proof methodology for the agent backend

## Status
Accepted (2026-06-20). Refines ADR-019 (the agent proof backend). Approved scope: the
skeleton-gate + fill backbone, **correctness-only** (implementation refinement deferred).

## Context

ADR-019's backend does **one-shot monolithic generation**: the spec statement goes in, a complete
`run` + proof comes out, with raw coqc stderr as the only feedback. Measured behaviour:

- **Easy / pinned specs** (`upper`, `grepf`, …): closes first-try (but the proof is a case-split —
  the elaborator's generic tactic would close it too).
- **One hard, *known-shape* proof** (`bsort` = insertion sort; `partition` = a custom preorder):
  closes, because the agent can adapt a familiar development.
- **A harder, multi-invariant proof** (`usort` = strict-sort + set-equality): the agent must invent
  a long, multi-lemma development *in a single pass* — and we observed generation latency with **no
  coqc verdict at all**, not a clean failure. No structure to lean on; feedback (a stderr from a
  120-line monolith) is useless even when a verdict arrives.

The agent needs **structure**, and — per the k4k invariant — the *harness* should drive and CHECK
that structure rather than hope the model supplies it.

## Decision

Replace one-shot generation with a four-phase methodology. A **deterministic harness orchestrates
focused agent steps**, each kernel-checked; the stochastic agent only fills holes; coqc judges at
every step. (`spec_rel`, the certified statement, remains elaborator-fixed — ADR-019.)

### Phase 1 — IMPLEMENT (naive, correctness-first)
The agent proposes the **most obviously-correct** `run`, the one whose proof is shortest, built
from stdlib/`Kalgebra` pieces — *not* an efficient one. The harness coqc-checks that `run`
type-checks against `Input`/`Output` (statement + `run`, no proof yet). *Cleverness is deferred;
correctness is the deliverable.* (Wirth stepwise refinement; refinement calculus.)

### Phase 2 — SKETCH (the skeleton gate — the keystone)
The agent returns (a) the **statements** of the helper lemmas `L1..Ln` it will need, and (b) the
**top-level proof** of `correct : forall i, spec_rel i (run i)` that *uses* them — with every `Li`
left `Admitted`. The harness coqc-checks this whole skeleton; **`Admitted` is legal here**
(intermediate scaffolding). If coqc accepts, the kernel has certified that **the decomposition is
type-correct and the lemmas are *sufficient* to close the goal — before a single lemma is proved.**
On failure the error is fed back; the agent revises the *decomposition*. This is the
propose/accept-or-reject pattern (ADR-013) applied to the proof **plan**: structure checked by the
kernel, not trusted from the model. (Lamport's structured proofs / Isar declarative style, made
checkable.)

### Phase 3 — FILL (focused, independent)
For each `Li`, the agent proves it **in isolation**: the harness builds a small obligation
(statement + `run` + already-proved lemmas + `Li` with its proof) and coqc-gates `Li` alone, with
**that lemma's** error fed back on retry. Small goal, small context → tight feedback, lower
generation latency, and independence (fill in declaration order; later lemmas may use earlier
ones). (Lemma-driven decomposition, CPDT-style; Ringer-style focused proof work; our
context-economy convention.)

### Phase 4 — ASSEMBLE + GATE
Splice `run` + all **proved** lemmas (admits removed) + the top-level proof + the extraction
directive, and run the existing `Certify.certify_v`: the **banned-word honesty gate forbids
`Admitted`/`Axiom`/`admit`**, then coqc re-checks the whole thing, extracts, compiles, cross-checks
the binary, and writes the TCB manifest. **No admit can survive into the certificate** — admits
exist only in the Phase-2/3 scaffolding, never in the Phase-4 artifact.

### Deferred — Phase 5, REFINE TO EFFICIENT (future ADR)
The agent proposes `run_fast` and proves `forall i, run_fast i = run i` (behaviour equivalence),
reusing the certificate. Modular and *not* needed for certification (correctness ≠ efficiency).
Out of scope for this version per the approved decision.

## Honesty invariants (unchanged from ADR-019, made explicit)
- The certified artifact (Phase 4) contains **no** `Admitted`/`Axiom`/`admit` — gated.
- `Admitted` appears **only** in the Phase-2 skeleton and the Phase-3 in-progress holes, which are
  *never* the artifact that earns the certificate.
- The agent never writes `spec_rel`; it proposes `run`, the decomposition, and the lemma proofs.
  coqc is the sole acceptance judge at every gate (type-check, skeleton gate, per-lemma, final).

## Why the skeleton gate is the keystone
It moves the expensive, failure-prone step earlier and makes it **cheap and kernel-checked**: a
wrong decomposition (insufficient lemmas, ill-typed plan) is caught in seconds against `Admitted`
stubs, instead of after the agent burns a long generation on an unprovable or misaimed monolith. It
also hands the agent a **correct scaffold** to fill — converting "write a 120-line proof" into "fill
this hole," which is what the model is good at and what keeps each step small.

## Grounding (this is not ad hoc)
Wirth stepwise refinement & Back/Morgan refinement calculus (naive-first, refine later); Lamport's
hierarchically-structured proofs and Isar declarative proof (state structure before tactics);
Chlipala (CPDT) lemma-driven development; Ringer proof repair / proof-state feedback. The novel k4k
contribution is **kernel-checking the plan** (the skeleton gate), not just the final proof.

## Risks / limits
- **Lemma dependencies / ordering** — v1 fills in declaration order with all prior lemmas in scope;
  a genuinely tangled dependency graph may need topological handling (later).
- **Insufficient decomposition** — caught by the skeleton gate (coqc rejects), fed back to the agent.
- **Per-lemma context** still needs the relevant algebra; but it is far smaller than the monolith.
- **More backend calls** (one per phase/lemma) — but each is smaller; net latency expected to drop,
  and lemmas are parallelizable.

## Implementation note
A new **structured** path in `lib/agent_proof.ml` (the existing one-shot path stays as a fallback):
the same external backend (`$K4K_PROOF_CMD`) is invoked several times with focused prompts (impl,
sketch, per-lemma), each followed by a coqc gate (`Certify.coqc_check`-style helper + the final
`certify_v`). Selected per a `--method=structured` flag (or env), so we can A/B it against one-shot
on `usort` and the existing specs.
