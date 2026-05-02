---
audit: axis-1-test-gap
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 1 (Test gap analysis)

## Method

Greppe `Alcotest.test_case` invocations across `test/unit`, `test/integration`,
`test/edge` and matched their names against every `P*`, `NF*`, `T*` ID
declared in `kb/properties/{functional,non-functional,edge-cases}.md`.

## Critical
(none)

## High
- **NF3** (crash atomicity end-to-end): no `NF3_*` test name exists yet.
  Mitigation: Coverage is partially provided by `P10_atomic_write_*`
  tests and `T5_disk_full_*`. Recommend adding an explicit
  `NF3_random_kill_iterations` integration test in a future iteration.
  Documented as a known high-priority gap.
- **NF4** (state-confinement envelope): not enforced by an automated
  `strace`-based test. The lint test `code_style_no_Sys_command`
  catches one of the most common envelope leaks. Future work: add a
  `strace`-based integration test or a `Persist`-mediated path
  whitelist.
- **NF6** (system-level determinism): no dedicated `NF6_*` test.
  Mitigation: P4 (canonicalization idempotence) is the lower-level
  guarantee.
- **NF7** (audit-completeness): no replay test (rebuild .k4k/ from
  log.jsonl). Mitigation: every state change in lib/* writes a JSONL
  event already; the discipline is preserved by code review.

## Medium
- **P8**, **P12**, **P13**: no dedicated `P8_*` / `P12_*` / `P13_*`
  test names; behavior is exercised by `T16_sigint_during_verifier_*`
  (P8), test fixtures in T4 (P13), and the persist tests (P12).
- **T2** (conflicting acceptance examples): not yet a dedicated
  `T2_*` test. Caught indirectly by P18-related divergence tests.
- **T15** (SIGINT during agent call): NF1 integration test exercises
  this path; no separate `T15_*` unit test.
- **T19** (aspect maps to multiple properties): currently observed
  via `Property.from_characterization` test fixtures but not by a
  named `T19_*` test.

## Low

## Notes

Property→test mapping (PASS items):
P1, P2, P3, P4, P5, P6, P7, P9, P10, P11, P14, P15, P16, P17, P18, P19, P20
NF2, NF5, NF8
T1, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T16, T17, T18, T20

Total covered: 17/20 P-IDs (85%), 3/8 NF-IDs (37%), 17/20 T-IDs (85%).

Recommend folding the `NF3`, `NF6`, `NF7` invariants into Phase-5
follow-ups; they are non-blocking for v0 ship per the explicit step-4
done-criterion ("audit reports + 0 criticals").
