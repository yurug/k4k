---
audit: axis-7-provability
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 7 (Provability)

## Method

1. `@invariant P<n>` annotations: every `.mli` file in `lib/` was
   greppe for `@invariant`. The `P20_invariant_coverage_at_least_80_percent`
   lint test enforces a threshold of 80% of P-IDs from
   `properties/functional.md` referenced in at least one `.mli`.
2. `properties/functional.md` ↔ `.mli` references: every `P<n>`
   referenced in code maps to a real entry. The 20 P-IDs of v0
   (P1..P20) are now all referenced.
3. KB cross-references: every `related:` ID and inline link inspected
   resolves to a real file in `kb/`.
4. `agent.*ok | agent.*pass | model.*confirm` regex returns only
   field names (e.g. `agent_invoke`), no conditional gates.
5. State transitions justified by deterministic predicates: every
   `if` branch in `Gap_step.step`, `Run_loop.loop_iter`,
   `Property.with_status` is reviewed — all gate on `(D, S, verifier
   output, user input)`.
6. KB-quiz: not yet re-run for step 4 (round-1 quiz: 10/10, recorded
   in `kb/reports/audit-round1-2026-05-02.md`). Re-run scheduled for
   Phase-5 KB-sync.

## Critical
(none)

## High
(none)

## Medium
- The 80% lint threshold currently passes at 100% (20/20). Future
  refactors that drop a P-reference will be caught by the same lint.

## Low

## Notes

P-ID coverage (extracted from `lib/*.mli`):

| ID  | Reference present | Notes                                 |
|-----|--------------------|---------------------------------------|
| P1  | yes (Parser, Kb_regen) | ownership inviolability             |
| P2  | yes (Stability)         |                                       |
| P3  | yes (Stability)         | added in step 4                       |
| P4  | yes (Canonicalize)      |                                       |
| P5  | yes (Gap_step, Run_loop)|                                       |
| P6  | yes (Property)          |                                       |
| P7  | yes (Logger, Error)     |                                       |
| P8  | yes (Sigint)            | added in step 4                       |
| P9  | yes (Run_loop, Backend_claude) |                                |
| P10 | yes (Persist)           |                                       |
| P11 | yes (Logger, Tty_status)|                                       |
| P12 | yes (Persist)           | added in step 4                       |
| P13 | yes (Run_loop)          |                                       |
| P14 | yes (Kb_regen)          |                                       |
| P15 | yes (Backend_*, Verifier_*) |                                   |
| P16 | yes (Kb_regen)          |                                       |
| P17 | yes (Property, Gap_step)|                                       |
| P18 | yes (Stability)         |                                       |
| P19 | yes (Stability)         |                                       |
| P20 | yes (Logger.Tty_status) | added in step 4                       |

Coverage ratio: 20/20 = 100%. The lint enforces ≥ 80% so future
refactors are bounded.
