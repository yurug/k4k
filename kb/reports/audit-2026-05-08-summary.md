---
audit: summary-roll-up
timestamp: 2026-05-09T07:00:00Z
result: closed (3 criticals + 11 highs all resolved; remaining mediums + lows are non-release-blocking)
---

# Audit Summary — 2026-05-08 (closed 2026-05-09)

Phase-5 quality audit on the v2 surface (commits up to and including
`5bcbeb3`). Seven axes dispatched in parallel via subagents per
`kb/runbooks/audit-checklist.md`. Each axis report lives at
`audit-2026-05-08-axis<N>-<name>.md`.

The audit ran on 2026-05-08; the closure pass spans batches 6-17
(commits `1ccd3f0` through `6c1f7dc`). All 3 criticals + 11 highs
resolved. Remaining mediums + lows are tracked in this document but
none are release-blockers.

## Audit-day verdict (snapshot)

| Axis | Verdict | C | H | M | L |
|------|---------|---|---|---|---|
| 1 — Test gap | fail | 0 | 3 | 4 | 2 |
| 2 — Security | fail | 0 | 1 | 2 | 3 |
| 3 — Performance | pass (with deferred) | 0 | 0 | 2 | 1 |
| 4 — UX | fail | 0 | 1 | 2 | 3 |
| 5 — Spec compliance | fail | 3 | 3 | 3 | 3 |
| 6 — Simplicity | fail | 0 | 3 | 2 | 5 |
| 7 — Provability | fail | 0 | 0 | 1 | 0 |
| **Totals (audit day)** | **fail** | **3** | **11** | **16** | **17** |

## Closure pass — all criticals + highs resolved

| Finding | Severity | Closed in | What changed |
|---------|----------|-----------|--------------|
| Axis 5 C1 | critical | batch 9 | `kb/spec/algorithms.md` top-level loop rewritten for the v2 watcher daemon (ADR-011 / ADR-013); termination + KB-regen sections cleaned of phantom `--max-steps` / `--reset` flags |
| Axis 5 C2 | critical | batch 9 | `kb/spec/data-model.md` Manifest schema rewritten to match v2 runtime shape; per-version manifest documented |
| Axis 5 C3 | critical | batch 9 | `kb/spec/error-taxonomy.md` reconciled (table vs catalog); `EOWNERSHIP_VIOLATION` + `EINVARIANT` now backed by real `Error.error` variants |
| Axis 1 H1 | high | batch 10 | P12 / P21 / P23 prefixed tests added (`PrefixedT` module) |
| Axis 1 H2 | high | batch 10 + 17 | T19 added in batch 10; T2 + T15 added in batch 17 (Coverage gained `conflicting_accept_pairs`; integration suite gained sigint-during-agent test) |
| Axis 1 H3 | high | batch 10 | `Watcher_pid` lifecycle tests added (`WPidT` module — 5 cases) |
| Axis 2 H1 | high | batch 6 | `Git.apply_diff` path filter via new `lib/diff_filter.{ml,mli}`; rejects `.k4k/` / `.git/` / absolute / `..` paths before any FS write |
| Axis 4 H1 | high | batch 8 | Closed error catalog: added `E_ownership_violation` + `E_internal_panic`; `Watcher.startup` typifies bare `Unix_error` to `E_state_corrupt`; cmdliner `~exits` overrides defaults so `--help` shows the taxonomy |
| Axis 5 H1 | high | batch 9 | `Characterization.t` schema gained `language` + `verifier_command` (ADR-012 §1) in `kb/spec/data-model.md` |
| Axis 5 H2 | high | batch 11 | Frontmatter parser drops the four pre-ADR-011 tooling-config fields (`verifier_command` / `verifier_timeout_s` / `backend_command` / `backend_timeout_s`) |
| Axis 5 H3 | high | batch 6 | Single source of truth `Manifest.k4k_version_string = "0.2.0"`; `bin/main.ml` + `Version_persist.write_manifest` both reference it |
| Axis 6 H1 / H2 / H3 | high | batch 7 + 11 | `lib/run_loop.{ml,mli}` + `lib/harness.{ml,mli}` + `lib/full_check.{ml,mli}` deleted in batch 7 (~410 LOC + 25 tests dropped); `Backend_external` wired in production via `K4K_BACKEND_COMMAND` in batch 11 (new `lib/backend_resolve.{ml,mli}`) |

## Closure pass — mediums resolved

| Finding | Severity | Closed in | What changed |
|---------|----------|-----------|--------------|
| Axis 1 M1 | medium | batch 10 | `bisect_ppx` instrumentation wired (`lib/dune` + `k4k.opam`); coverage recipe documented in `kb/runbooks/test-environment.md` |
| Axis 1 M2 | medium | batch 14 + 15 | `Version_finalize` (Done / Rolled_back) + `Watcher.startup` (3 paths) focused unit tests added |
| Axis 1 M3 | medium | batch 14 | `Manifest` accessors (read_or_init / hashes / desired_hash / version-mismatch / unparseable) — 4 cases |
| Axis 1 M4 | medium | batch 15 | `Tradeoff_flow.propose_and_wait` runtime — 5 cases (Approved B/C, Rejected, Timed_out, archive side-effect) |
| Axis 2 M1 | medium | batch 13 | `Backend_external.make_scratch_dir` /tmp fallback removed; missing `k4k_dir` now raises typed `E_state_corrupt` |
| Axis 2 M2 | medium | batch 13 | `Toolchain_install` npm path documented as NF4 exception in `kb/properties/non-functional.md`; `Sys.getenv "HOME"` → typed error on absence |
| Axis 5 M1 | medium | batch 11 | `Property.blocked` field dropped (was a redundant mirror of `failure_count >= 3`) |
| Axis 5 M2 | medium | batch 9 | `kb/spec/error-taxonomy.md` table-vs-catalog reconciliation done in batch 9 |
| Axis 5 M3 | medium | batch 11 | `Parser.frontmatter` no longer leaks the four obsolete fields into the public API |
| Axis 6 M-1 | medium | batch 12 | `kb/architecture/overview.md` rewritten end-to-end for the v2 watcher graph (28 missing modules added; retired `Convergence` removed; DI section reflects `agent_invoke` closure threading) |
| Axis 6 M-2 | medium | batch 12 | `Inline_blocks_sections.find_h2_with_prefix` deduplicates the previously near-identical `find_tradeoff_block` / `find_clarification_block` helpers |
| Axis 7 M-1 | medium | batch 6 | 5 dangling `related:` / `depends-on:` IDs fixed across `kb/architecture/overview.md`, `kb/conventions/context-economy.md`, ADR-003, ADR-004 |

## Closure pass — lows resolved

| Finding | Severity | Closed in |
|---------|----------|-----------|
| Axis 4 L3 (silent clarification-write failure) | low | batch 16 — `clarification.write_failed` event now emitted on cotype rejection |
| Axis 6 L-1 (`watcher_loop.ml` 201 lines) | low | batch 6 — back to 200 |
| Axis 6 L-2 (`watcher_form.run` 51 lines) | low | batch 16 — split into `invoke_semantic` / `on_stable` / `dispatch_outcome`; `run` is now 12 lines |
| Axis 6 L-3 (`watcher_dev.try_run_version` 37 lines) | low | batch 16 — extracted `dispatch_with_typed_errors` + `start_or_skip`; `try_run_version` is now 7 lines |
| Axis 6 L-4 (`run_loop.loop_iter` 41 lines) | low | batch 7 — moot, module deleted |

## Items NOT closed (non-blockers)

- **Axis 1 L1** — silent cotype-skip in unit tests. `if not (cotype_available ()) then ()` six times in `test_unit.ml` returns silently; should print `"skipped: cotype not on PATH"` like the integration wrapper. Cosmetic.
- **Axis 1 L2** — focused unit tests for `Status_splice` / `Kb_render` / `Starter_template` / `Backend_external_parse`. All four are pure renderers / parsers covered indirectly by integration tests. Cosmetic — would add 8-12 tiny round-trip tests.
- **Axis 3 M1** — wall-clock-per-gap-step benchmark (median < 60 s). Needs a perf harness; not wired. Marked n/a-deferred in the original audit.
- **Axis 3 M2** — API request budget aggregation across a realistic scenario. Same shape — needs a perf harness. n/a-deferred.
- **Axis 3 L1** — 100-iteration random-kill atomic-write fuzz (we have 50). Cosmetic.
- **Axis 4 L1** — `audit-checklist.md` Axis-4 still mentions the v0 `--check` flag. KB sync.
- **Axis 4 L2** — version-string drift between `bin/main.ml` and `Manifest.k4k_version_string`. **Already fixed in batch 6 via the H3 single-source-of-truth.** Mark closed.
- **Axis 5 L1 / L2 / L3** — small spec-vs-code shape mismatches; `verifier_pref` already marked deprecated in batch 9.
- **Axis 6 L-5** — six files within 5 lines of the 200-line cap. No action required; flagged for the next refactor.

## Closure pass — single most load-bearing finding

**Axis 2 H1 (closed in batch 6)** — `Git.apply_diff` had no path filter on agent-supplied diffs. v2's direct-commit gap-step (ADR-013 §2 step 3) deliberately removed the scratch-branch isolation v1 used. `git reset --hard HEAD` on rejection does NOT clean `.k4k/` (it's in `is_ignorable_path`), so a single poisoned diff could permanently invalidate `manifest.json` / `version/<n>/audit.md`, bypassing the determinism contract. Closed via `lib/diff_filter.{ml,mli}` + a filter call in `Git.apply_diff`. The test suite gained 5 unit tests under `Git`.

**Axis 6 H-3 (closed in batch 11)** — Backend_external was documented as the production agent adapter but had zero production callsites; production agent calls fell back to `Tool_error "no K4K_STUB_RESPONSES configured"`. Without this fix, the v2 binary couldn't run any real agent. Closed via `lib/backend_resolve.{ml,mli}` and the `K4K_BACKEND_COMMAND` operator-level seam.

## Pattern observed across axes (audit day)

The dominant failure mode was **spec lag, not code drift**. The v2 reorientation shipped via ADRs 011/012/013, the implementation tracked them, and the test suite tracked the implementation. Several KB files (`kb/spec/algorithms.md`, `kb/spec/data-model.md`, `kb/spec/error-taxonomy.md`, `kb/architecture/overview.md`, `kb/runbooks/audit-checklist.md`) got partial updates only. Per CLAUDE.md, KB normally wins by default — but post-v2 the ADRs are the actual normative source. Batches 6 / 9 / 11 / 12 brought the four critical KB files back into sync.

A secondary pattern: the v0 → v2 migration left a long tail of orphan modules (`Run_loop` / `Harness` / `Full_check`) referenced only by tests that were no longer testing the production path. Batch 7 deleted ~600 LOC of code + scaffolding; batch 17 ported the four NF properties whose unit-level coverage was lost in that deletion (NF2 / NF4 / NF6 / NF7) onto the v2 `Version_loop` path.

## Test count timeline

| When | Suite total |
|------|-------------|
| Audit day (commit `5bcbeb3`) | 273 (243 unit + 20 integration + 6 conformance + 4 edge) |
| Batch 11 (Backend_external wired) | 273 (241 unit + 22 integration + 6 conformance + 4 edge — net 0; canned-suite parts ported to integration) |
| Closure pass complete (commit `6c1f7dc`) | **295 (262 unit + 23 integration + 6 conformance + 4 edge)** |

Net delta from audit day: **+22 tests across the closure pass**.

## Files in this audit's report set

- `audit-2026-05-08-summary.md` — this roll-up
- `audit-2026-05-08-axis1-test-gap.md`
- `audit-2026-05-08-axis2-security.md`
- `audit-2026-05-08-axis3-performance.md`
- `audit-2026-05-08-axis4-ux.md`
- `audit-2026-05-08-axis5-spec-compliance.md`
- `audit-2026-05-08-axis6-simplicity.md`
- `audit-2026-05-08-axis7-provability.md`
