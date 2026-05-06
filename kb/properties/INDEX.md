---
id: properties.index
type: index
summary: Routing table for the property layer — functional invariants, non-functional measurable criteria, edge cases.
domain: properties
last-updated: 2026-05-02
depends-on: []
refines: []
related: [spec.index, conventions.testing-strategy, runbooks.audit-checklist]
---

# Properties — Routing Table

## How to use this index

Every behavior k4k must enforce is named here by ID:
- **P-series**: qualitative invariants (`P1`, `P2`, …)
- **NF-series**: measurable non-functional criteria (`NF1`, `NF2`, …)
- **T-series**: edge-case targets (`T1`, `T2`, …)

Source code references these IDs in `@invariant` annotations; tests reference them in test names (`P5_non_regression_under_partial_patch`, `T15_sigint_during_agent_call`).

## Routing table

| If you need...                                              | Read this file        | Key questions                                                     |
|-------------------------------------------------------------|-----------------------|-------------------------------------------------------------------|
| The qualitative invariants of k4k's behavior                | `functional.md`       | What guarantees does k4k make about determinism, ownership, …?    |
| Quantitative thresholds (latency, memory, audit completeness) | `non-functional.md` | What's the Ctrl-C latency budget? The memory ceiling?             |
| Boundary conditions and their expected behavior             | `edge-cases.md`       | What does k4k do on disk-full? On a user-edited `## k4k:clarification:*` section (cotype conflict)? |

## File counts

- `functional.md`: P1..P20 (20 entries)
- `non-functional.md`: NF1..NF8 (8 entries)
- `edge-cases.md`: T1..T20 (20 entries)

## Reading order

`functional.md` first (defines the language used by the others), then `non-functional.md`, then `edge-cases.md`.
