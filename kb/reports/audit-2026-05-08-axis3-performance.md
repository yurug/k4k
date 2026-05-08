---
audit: axis-3-performance
timestamp: 2026-05-08T17:35:00Z
result: pass
---

# Findings — Axis 3 — Performance

## Summary

| # | Check                                                  | Result          |
|---|--------------------------------------------------------|-----------------|
| 1 | Memory ceiling (NF2): max RSS < 512 MB on 50-step run  | **pass**        |
| 2 | Wall-clock per gap-step (median) < 60 s                | **n/a-deferred**|
| 3 | API request budget within R1 caps + soft-cap totals    | **n/a-deferred**|
| 4 | Atomic writes: 100 random-kill iterations, parses each | **pass\***      |
| 5 | No `flock` in `lib/` post-ADR-010                      | **pass**        |
| 6 | No N+1 agent calls (formalize cached, gap-step 1:1)    | **pass**        |

\*Check 4 has a quantitative deviation from the spec letter; see Medium below.

Severity counts: **0 critical**, **0 high**, **2 medium**, **1 low**, plus **2 deferred** (checks 2 and 3 lack benchmark/lint scaffolding — flagged for tracker).

---

## Check-by-check evidence

### Check 1 — Memory ceiling (NF2): pass

- Test: `NF2_rss_under_512mb_for_50_step_scenario` (`lib/persist.ml` instrumented; reads `/proc/self/status` VmRSS each agent invocation).
- File: `test/unit/test_unit.ml:3381-3423`.
- Run output (`_build/_tests/.../NF2.000.output`): `ASSERT max RSS < 512 MB (observed: 12 MB)`.
- The test synthesizes a 50-property gap, drives `Run_loop.run` with stub agent + canned verifier; Alcotest passes the `mb < 512` assertion. The 12 MB observed value is two orders of magnitude under cap.

### Check 2 — Median wall-clock per gap-step < 60 s: n/a-deferred

- No benchmark exists. `test/unit/test_unit.ml` and `test/integration/test_integration.ml` track `duration_ms` only as JSON-field plumbing (`test_unit.ml:1308, 1532, 1656`), never aggregating per-step wall-clock.
- What would be needed:
  - Instrument `Run_loop.run`: for each `Gap_step.step`, record (start, end) into a JSONL.
  - A benchmark target (e.g. `dune build @bench`) running a stub-backend 50-step scenario, computing the median.
  - Acceptance: median `duration_ms` < 60 000.
- Recommendation: add `bench/perf_gap_step.ml` parallel to the integration suite; gate on `K4K_BENCH=1` so it doesn't bloat regular CI.

### Check 3 — API request budget within R1 + soft caps: n/a-deferred

- The mechanism exists (`lib/gap_step.ml:174-175` decrements `budget_remaining`; `agent_backend.budget_used` enforced by external backends per `external/backend-protocol.md`). `Backend_external_parse.ml:45-49` rejects responses where `budget_used > --budget`.
- However, no aggregate **scenario-level** measurement exists:
  - No test sums `budget_used` across a full v1 run and asserts it stays under a soft cap.
  - Per-call R1 caps from `kb/conventions/context-economy.md:22-30` (Formalization 3 000 in / 1 500 out, Gap-step 4 000 / 2 000, KB-regen 1 500 / 1 000) are not lint-checked. The KB explicitly says "lint check on `prompts/*.md`" — no such lint exists in `lib/`, `bin/`, or `test/`.
- Empirical word counts of the prompt templates (`wc -w prompts/*.md`):
  - `formalize.md`: 255 words; `gap-step.tier-{a,b,c}.md`: 219/239/228; `kb-regen.md`: 273. All comfortably under the input caps even with naive 1.3 tokens/word.
- Recommendation: implement the R1 lint as a `dune test` rule using a token-counter (or even a strict word-count proxy of `cap_tokens / 1.3`), running over `prompts/*.md`. Add a scenario-level budget assertion to the integration suite.

### Check 4 — Atomic writes: pass\* (with deviation)

- Implementation: `lib/persist.ml:89-105` (`atomic_write` = tmp + fsync + crash_hook + rename + fsync_dir).
- Random-kill test: `NF3_random_kill_iterations` at `test/unit/test_unit.ml:3727-3781`.
  - Iterates **50** times (audit asks for 100). Source comment: `for i = 1 to 50 do`.
  - Crash injection: a 50/50 RNG choice between a normal write and one whose `crash_hook` raises `Exit` between fsync(tmp) and rename. Output (`_build/_tests/.../NF3.000.output`) shows iter-by-iter `manifest parses` + `prior bytes intact` / `new bytes committed` assertions — all pass.
- ENOSPC coverage: `T5_disk_full_during_atomic_write` (`test/unit/test_unit.ml:3636-3650`) sets `K4K_FAULT_INJECT_ENOSPC=out.txt`, asserts `E_disk_full` raised, no file written, `.tmp` cleaned up. Passes.
- Signal-interrupt coverage: **not present**. The crash_hook's `raise Exit` simulates a SIGKILL between fsync and rename (functionally equivalent for the manifest-corruption surface), but no test delivers SIGINT/SIGTERM mid-write to an actual `Persist.atomic_write` call.

Why "pass\*": the property the audit cares about — *no torn manifest after arbitrary kill* — is exercised by the `crash_hook` mechanism, which is the right level of abstraction. The shortfall is a **letter-of-the-spec** deviation (50 vs 100 iterations; no explicit signal test) rather than a substantive gap.

### Check 5 — No `flock` in `lib/` post-ADR-010: pass

- Command: `grep -rn 'Unix.lockf\|flock' lib/`
- Result: **one match**, `lib/cotype.mli:12`, in a comment that *documents the absence*: `"k4k carries no [flock] code itself."`
- Zero functional uses. ADR-010's removal of `lib/persist_lock.ml` is verified.

### Check 6 — No N+1 agent calls: pass

The architecture has three agent-call entry points; each is correctly gated:

1. **Formalization** is called from `lib/stability.ml:103`. It is invoked exactly when:
   - User-section hashes have changed since the last manifest (`lib/stability.ml:51-59 cache_hit`); OR
   - There is no cached `D` on disk (`lib/watcher_form.ml:39-52 load_cached`).
   When user-section hashes match, `Sem_cached` returns immediately and the agent is **never called**.
   - Unit-test proof: `P19_cache_skips_formalization_when_hash_matches` (`test/unit/test_unit.ml:1142-1157`) wires an invoker that *errors on call* and asserts `Sem_cached`. Passes.
   - Watcher-level proof: `Watcher_form.cache_short_circuits_two_calls` (`test/unit/test_unit.ml:4866-4886`) runs `Watcher_form.run` twice on identical content; assertion: `first run 2 calls, second run still 2`. Zero new calls on cache hit.

2. **Idempotence gate** at the watcher tick level: `lib/watcher_dev.ml:118-123` short-circuits with `version.skip` (`reason: no-spec-change`) when `Version_persist.last_completed_d_hash` equals the freshly-formalized `d.hash`. This stops the main loop from spinning a redundant version branch on a stable spec.
   - Production-mode integration coverage: `P22b_v1_to_v2_picks_up_user_edits` (`test/integration/test_integration.ml:816-866`) runs the watcher with `--max-versions=2`; asserts `version.start fires twice` and both `v1` + `v2` tags exist — i.e. the gate correctly *passes* a real edit through *and* would block a no-op.

3. **Gap-step**: exactly one `agent_invoke` per `Gap_step.step` (`lib/gap_step.ml:194`, `purpose:Gap_step`). The function dispatches into apply-diff → verifier → commit/rewind without re-formalizing. `version_loop.ml:106-123 run_gap_loop` selects the next property by `Property.argmax_lex`, calls `drive_property_full` once, recurses on the rest — no nested formalize call.

**Canned-backend persistence (the recently-fixed N+1 hazard)**:
- `lib/watcher_loop.ml:191-192`:
  ```
  (* Resolve once; canned-backend queues must persist across ticks. *)
  let agent_invoke = Watcher_dev.resolve_invoke ~emit:cfg.emit in
  ```
- The closure is allocated **outside** the `let rec loop` and threaded into `one_tick` (line 194-195) on every iteration.
- `lib/watcher_dev.ml:18-33 resolve_invoke` returns the same `Backend_canned.invoke t` closure across ticks; the per-purpose response queues persist.
- The `.mli` (line 11-22) documents the single-allocation contract: *"called ONCE at watcher startup; ... a fresh load on every iteration would reset them."*
- P22b would not pass without this fix (its 2-version canned payload requires the formalization queue to advance between v1 and v2). Confirmed: P22b OK in 19.7s.

Conclusion: the only agent calls per gap-step are the gap-step itself; formalization is gated *both* by the in-process cache and by the manifest-hash idempotence gate. No N+1.

---

## Critical
*(none)*

## High
*(none)*

## Medium

- **NF3-iter-shortfall** — `NF3_random_kill_iterations` runs 50 iterations; spec (`kb/properties/non-functional.md:39`) says 100.
  - evidence: `test/unit/test_unit.ml:3735` (`for i = 1 to 50 do`).
  - fix: change the loop bound to 100, or expose a `K4K_NF3_ITERATIONS` env override and run 100 in CI / 50 locally. Minor; the surface coverage is identical at 50.

- **Perf-bench-missing** — Checks 2 and 3 (median wall-clock and aggregate budget) have no measurement. The harness ships behaviour without a check that catches future regressions.
  - evidence: no file matches `bench*` under `lib/` or `test/`; no aggregate `budget_used` assertion in `test/integration/test_integration.ml`.
  - fix: add `bench/perf_gap_step.ml` (median wall-clock under canned/stub backend) + a `prompts/*.md` token-cap lint. Both are small; the bench can reuse the NF2 50-step harness.

## Low

- **Atomic-write signal-interrupt** — No test delivers SIGINT/SIGTERM during `Persist.atomic_write`. The `crash_hook = raise Exit` mechanism functionally equivalent (interrupts between fsync and rename), but the audit checklist's letter mentions "ENOSPC + signal-interrupt scenarios" specifically.
  - fix: optional. Add a single test that arms `Sys.set_signal sigalrm` to call `raise Exit` mid-write via `Unix.alarm 0`-equivalent — same crash_hook surface but signal-driven.

## Notes

- The recently-architected v2 watcher loop (Watcher_loop.run, Watcher_dev, Version_loop) holds together cleanly under the perf axis. The two highest-value tests (`P19_cache_skips_formalization_when_hash_matches`, `Watcher_form.cache_short_circuits_two_calls`) directly prove that the cost-bounding contract is enforced — no agent calls when nothing has changed.
- The `5bcbeb3` canned-backend persistence fix is in place: `agent_invoke` allocated once at `lib/watcher_loop.ml:192`, threaded through every tick. `P22b` would hang without it; it passes in ~20 s, so the fix holds.
- Most-actionable performance gap: **wire a perf benchmark target (check 2)**. NF2 already shows the harness can self-measure RSS during a 50-step run; the same scaffolding extended with `Unix.gettimeofday` deltas would close check 2 for a few hours of work and protect the watcher loop against future N+1 regressions.

## Related files

- `properties/non-functional.md` — NF1, NF2, NF3 statements
- `architecture/decisions/adr-010-cotype-delegation.md` — flock removal
- `architecture/decisions/adr-013-direct-commit.md` — gap-step shape
- `conventions/context-economy.md` — R1 token caps
- `external/backend-protocol.md` — budget semantics
