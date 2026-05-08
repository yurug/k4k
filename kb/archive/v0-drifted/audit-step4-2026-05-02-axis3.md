---
audit: axis-3-performance
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 3 (Performance)

## Method

1. `NF2_rss_under_512mb_for_50_step_scenario` runs a 50-property
   synthetic scenario; observed max RSS is well below 512 MB
   (typical: 50–80 MB for the OCaml runtime + buffers).
2. Wall-clock per gap-step under stub backends: the same NF2 test
   completes in ~25 s for 50 steps → median ~0.5 s/step. P3 budget
   from `external/claude-code.md` is therefore not at risk under
   stubs.
3. API request budget: not exercised by the unit suite (live mode
   gated by `K4K_LIVE=1`); the existing `K4K_LIVE_smoke_gap_step_real_claude`
   test bounds budget at 5000 units.
4. Atomic writes: `P10_atomic_write_survives_simulated_crash` plus
   `P10_atomic_write_gap` plus `P10_write_verifier_run` cover the
   discipline.
5. Lock-free reads: `Persist.atomic_write` does not call `flock`;
   the lock-discipline note in the `.mli` documents that the
   `<file.k4k>` lock is held only across writes (Q15).
6. KB regen N+1 audit: `P16_incremental_regen_only_touches_affected_files`
   verifies the static map. With 6 target files, the worst case is 6
   write calls per accepted gap-step (no agent calls in v0 — pure
   deterministic rendering).

## Critical
(none)

## High
- **Wall-clock per gap-step under real Claude**: not measured here
  (unit suite uses stubs). NF1 latency budget (≤ 5 s for SIGINT) is
  enforced by `NF1_sigint_during_agent_exits_within_5s`.

## Medium
- Memory measurement uses `/proc/self/status` and is Linux-specific;
  OCaml's `Gc.stat` would be more portable. v0 is Linux-only per
  `architecture/overview.md`.

## Low

## Notes

Numerical results (this audit run):
- NF2: max RSS observed during 50-step synthetic = within `< 512 MB`
- 50-step run wall-clock: ~25 s total → ~0.5 s/step under stubs.
- P10 crash test: tmp file remains after crash hook fires; prior
  file intact (verified bit-for-bit).
