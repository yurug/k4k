---
id: adr-005
type: decision
summary: The harness's determinism contract holds on a *canonicalized* AST, not on raw agent output. Two formalization runs detect ambiguity by canonical-hash comparison.
domain: architecture
last-updated: 2026-05-02
depends-on: [domain.prd, spec.algorithms]
refines: []
related: [adr-003, properties.functional]
---

# ADR-005: Determinism on canonical AST; two-run formalization

## Status
Accepted (2026-05-02).

## Context
NOTES.md demands a deterministic harness. The harness calls a stochastic agent backend during the formalization pass (translating the user's spec into a typed AST). Two runs of the same agent on the same input may produce *syntactically* different AST representations even when they are *semantically* equivalent (e.g. fields in different order, identifiers paraphrased).

If the harness compared raw outputs:
- Equivalent runs would falsely register as ambiguous.
- True ambiguity would be invisible behind cosmetic noise.

If the harness ran the agent only once:
- True ambiguity would be undetectable. The agent would silently pick one reading and proceed.

We need a comparison that ignores cosmetic noise but catches genuine semantic divergence; and we need at least two independent samples to compare.

## Decision
1. **Canonicalize the AST after parsing.** Sort fields with no semantic order; squeeze whitespace in free-form strings; *do not* rename user-provided identifiers (their text carries meaning per the test-name convention).
2. **Hash the canonicalized form** (SHA-256 of stable JSON). Two ASTs are equivalent iff their canonical hashes match.
3. **Run the formalization pass at least twice** with independent agent calls (different seeds / different stochasticity). Accept iff both canonical hashes match.
4. **On hash mismatch**, emit a *divergence report* listing the first AST node where the two trees differ (deterministic walk order). Mark unstable; append clarification to the interaction file.
5. **The harness's determinism contract** (`P4`, `NF6`) is stated against canonical hashes, not raw outputs.

## Consequences
- The harness consumes ≥ 2 agent calls per stability check (when not cached). Mitigated by caching keyed on user-section hashes (`P19`).
- "Cosmetic" agent variance is invisible to the harness — good.
- Genuinely ambiguous specs always surface as instability — good, and this is the user's only feedback channel.
- Cost: the canonicalization function is non-trivial and must itself be tested for stability (idempotent: `canonicalize(canonicalize(x)) == canonicalize(x)`; structural-equivalence-preserving).

## What this means for implementers
- **`lib/Canonicalize` is pure.** No I/O. Property-based tests assert idempotence and that canonicalization preserves semantic equivalence on a corpus of paraphrased pairs.
- **Never compare raw agent outputs anywhere.** Always canonicalize first. Lint check on the source for forbidden patterns.
- **The "two runs" rule is a minimum, not a target.** We may run a third under conflict to gather more evidence, but never *fewer* than two.
- **Identifiers from the user (e.g. `ArgSpec.name`) are not renamed.** They carry semantic meaning the harness must preserve.
