---
audit: axis-1-test-gap
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 1 (Test gap analysis)

## Method

Grepped `Alcotest.test_case` invocations across `test/unit`,
`test/integration`, `test/edge` and matched their names against every
`P*`, `NF*`, `T*` ID declared in
`kb/properties/{functional,non-functional,edge-cases}.md`.

Re-audited after Phase 5 added the four NF tests:
`NF3_random_kill_iterations`, `NF4_state_confinement_envelope`,
`NF6_determinism_under_repeat`, `NF7_jsonl_replay_round_trip`.

## Critical
(none)

## High
(none — all four prior highs closed in Phase 5)

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
NF1, NF2, NF3, NF4, NF5, NF6, NF7, NF8
T1, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T16, T17, T18, T20

Total covered: 17/20 P-IDs (85%), 8/8 NF-IDs (100%), 17/20 T-IDs (85%).

### Phase-5 closures

The four high-severity gaps from the Phase-4 dry-pass have all been
closed by named tests. Each test exercises the property end-to-end (not
merely a module-level reproducer), per the Phase-5 requirements:

- `NF3_random_kill_iterations` (test/unit/test_unit.ml, NF3T module):
  50 iterations of randomly-timed crash injection through
  `Persist.atomic_write` against `manifest.json`; asserts manifest
  always parses and that the prior bytes are intact across crashed
  iterations. Reuses the existing `crash_hook` plumbing from P10 (no
  new infrastructure invented).
- `NF4_state_confinement_envelope` (test/unit/test_unit.ml, NF4T):
  drives a small synthetic harness scenario with `Backend_stub` +
  `Verifier_stub` and a debug-only trace of every Persist write
  (`K4K_TEST_TRACE_WRITES=<file>`); asserts every observed path falls
  under `<file.k4k> ∪ .k4k/<*>/ ∪ <workdir>/`. Production builds
  ignore the env var.
- `NF6_determinism_under_repeat` (test/unit/test_unit.ml, NF6T):
  runs `Stability.semantic_check_with_backend` + gap construction
  twice on the same fixture with `Backend_stub` configured for stable
  output; asserts byte-equal `desired/spec.json` and
  `gap/properties.json` after stripping the documented timestamp
  fields (`last_run`, `last_stable_at`, `ts`, `duration_ms`,
  `last_check`, `last_step`, `manifest.last_*`).
- `NF7_jsonl_replay_round_trip` (test/unit/test_unit.ml, NF7T):
  drives a small canned scenario through `Run_loop.run`, then walks
  `.k4k/log.jsonl` to reconstruct the high-level state (set of
  property IDs, established subset, manifest presence) and diffs
  against the actual on-disk state (gap file + agent-runs verdicts).
  Equality required modulo timestamps. The `gap.persist` JSONL event
  was added in `Run_loop` to make the log self-sufficient.

### Plumbing added (flag for KB sync)

- **Env var `K4K_TEST_TRACE_WRITES=<file>`**: when set, every
  `Persist.atomic_write` and `Persist.append_jsonl_line` appends its
  target path to `<file>`. Test-only; default behaviour unchanged.
  Documented in `lib/persist.mli` alongside the existing
  `K4K_FAULT_INJECT_ENOSPC`, `K4K_STUB_RESPONSES`, `K4K_STUB_SLOW`.
- **JSONL event `gap.persist`**: emitted in `Run_loop` after every
  `persist_gap` call (initial + per-step). Carries
  `{count, properties:[{id,status}]}`. Required by NF7's replay
  reconstruction. Five existing tests still pass — the addition is
  purely additive.

### Phase-5 iterations

- Iteration 1: scaffolded all four NF tests (red); two failed
  (NF6 due to `Full_check.run` invoking the coverage check on a
  minimal fixture; NF7 due to a shadowed `focus` argument and gap
  reconstruction not accounting for established props leaving the
  gap file).
- Iteration 2: switched NF6 to call
  `Stability.semantic_check_with_backend` directly (the property
  measures the formalization+gap pipeline, not coverage); fixed
  NF7's verifier shim and extended `actual_state` to merge gap.json
  with `agent-runs/<id>/verdict.json`. All four NF tests green.

Total test count: 173 (was 162; +11 = 4 main NF tests + 7 helpers).
