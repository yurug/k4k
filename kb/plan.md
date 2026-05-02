---
id: plan
type: procedure
summary: v0 implementation plan — 4 vertical slices, each producing a runnable program. Step 1 ships a CLI that builds, parses, and persists. Steps 2–4 add depth.
domain: meta
last-updated: 2026-05-02
depends-on: [domain.prd, properties.functional, properties.non-functional, properties.edge-cases, architecture.overview]
refines: []
related: [conventions.testing-strategy, runbooks.audit-checklist]
---

# k4k v0 — Implementation Plan

## Conventions

- Each step runs a Ralph Loop (max 5 iterations). If a step does not converge, stop and split — do not raise the iteration cap.
- Each step ends with a runnable, observably-progressed `k4k` binary. No "step 1 is types only" — step 1 *runs*.
- Property IDs (P/NF/T) reference `kb/properties/`. Acceptance criteria cite specific tests, written before implementation in TDD style.
- Stubs (`Backend_stub`, `Verifier_stub`) ship in `lib/` from step 1; they are also used in production via `--backend=stub` for reproducible demos.

## Step 1 — Vertical slice: parse + structural stability + persistence

**Goal:** `k4k --check <file.k4k>` runs end-to-end on a structurally well-formed file. No agent calls. No gap-step loop. The CLI exists, parses argv, reads the interaction file, validates structure, writes `.k4k/manifest.json`, exits with the right code.

**Modules created:**
- `bin/main.ml` — argv parsing, DI wiring, top-level exception handler
- `lib/Error` — closed error hierarchy from `conventions/error-handling.md`
- `lib/Logger` — stderr text + `.k4k/log.jsonl` JSONL; secrets scrubbing
- `lib/Persist` — atomic writes (tmp + fsync + rename), `flock` discipline, `.k4k/` initialization
- `lib/Parser` — pure parse of `<file.k4k>`: YAML frontmatter + ownership-tagged sections
- `lib/Stability` — structural stage only (`stability_check_structural`); semantic stage stubbed to "pass"
- `lib/Harness` — top-level loop; in step 1 it terminates after structural check
- `lib/Backend_stub` — DI-injectable stub; no agent calls happen yet
- `lib/Verifier_stub` — DI-injectable stub; no verifier calls happen yet

**Modules NOT created in step 1:** `Canonicalize`, `Gap_step`, `Kb_regen`, `Backend_claude`, `Verifier_dune_ocaml`, `Logger.Tty_status`.

**Properties enforced:** P1 (ownership inviolability), P7 (closed error taxonomy), P10 (atomic writes), P11 (stdout/stderr discipline), P12 (file-locking discipline), P13 (fresh-read per step — trivially: only one step), P15 (pluggable backend conformance — stubs satisfy the signature).

**Edge cases tested:** T1 (empty file), T6 (non-UTF-8), T7 (oversize), T17 (stale manifest version).

**Acceptance tests** (named per `conventions/testing-strategy.md`):
1. `P1_ownership_user_section_unchanged` — round-trip a fixture; assert byte-equality of every `owner=user` region.
2. `P7_unknown_error_is_invariant_violation` — assert no `failwith` outside a 64+ exit path.
3. `P10_atomic_write_survives_simulated_crash` — inject a crash hook between `tmp` write and `rename`; assert prior file intact.
4. `P11_stdout_pipeable` — pipe `k4k --check <stable>`, assert single-line `stable (structural-only)\n`; pipe stderr separately, assert empty at default verbosity.
5. `T1_empty_file_is_unstable` — exit 1, `EUNSTABLE` stderr line.
6. `T7_oversize_rejected` — exit 1, `EFILE_TOO_LARGE` stderr line.
7. `S5_check_subcommand_exits_0_when_stable_structural` — integration test with a hand-crafted fixture.

**Definition of done:**
- `dune build @check` clean.
- `dune build @runtest` green.
- ≥ 3 tests per source file in `lib/`.
- All modules ≤ 200 lines, all functions ≤ 30 lines (`conventions/code-style.md`).
- `k4k --check tests/fixtures/well-formed-structural.k4k` exits 0; `k4k --check tests/fixtures/empty.k4k` exits 1; `.k4k/manifest.json` and `.k4k/log.jsonl` are created.

---

## Step 2 — Semantic stability: formalization pass + canonicalization

**Goal:** `k4k --check <file.k4k>` runs the full two-run formalization protocol against the agent backend, canonicalizes the AST, persists `D` to `.k4k/characterization/desired/spec.json`. Coverage-checklist enforcement makes incomplete specs unstable.

**Modules created:** `lib/Canonicalize` (pure); extend `lib/Stability` with `stability_check_semantic`; `lib/Backend_claude` (subprocess `claude -p`, JSON output parsing per `external/claude-code.md`).

**Modules touched:** `lib/Persist` (add `desired/spec.json` write), `lib/Parser` (no change — section ids drive everything), `lib/Backend_stub` (add weakness-profile mode per `conventions/context-economy.md`).

**Properties enforced (new):** P2 (two-stage stability), P3 (pass/fail), P4 (determinism on canonical AST), P18 (two-run minimum), P19 (cache by user-section hash), NF6 (system-level determinism), NF8 (weakness-profile passes).

**Edge cases tested:** T9 (both formalization runs invalid), T10 (formalization runs disagree), T13 (budget exhausted during formalization).

**Acceptance tests:**
1. `P4_canonicalization_idempotent` — qcheck: `canonicalize(canonicalize(x)) = canonicalize(x)`.
2. `P4_canonicalization_preserves_structural_equivalence` — qcheck: paraphrased pairs hash equal.
3. `P18_two_run_minimum_detects_divergence` — `Backend_stub` returns two non-equivalent ASTs; assert `EUNSTABLE` + divergence report at `.k4k/agent-runs/<id>/divergence.json`.
4. `P19_cache_skips_formalization_when_hash_matches` — second run on unchanged file: assert exactly zero formalization invocations in JSONL.
5. `NF8_formalization_under_weakness_profile` — entire test suite passes against `Backend_stub` weakness profile.
6. `T13_budget_exhausted_during_formalization` — stub agent reports budget exhaustion mid-call; assert `EBUDGET` + no partial `desired/spec.json`.

**Definition of done:**
- All step-1 acceptance still green.
- The full test corpus runs against the weakness profile, not just Claude.
- A real `claude -p` call produces a parseable formalization for at least one fixture (smoke test, not in CI by default; runnable via `dune runtest --force --root . --display=short` with `K4K_LIVE=1`).
- `.k4k/characterization/desired/spec.json` validates against the JSON schema derived from `Characterization` (`spec/data-model.md`).

---

## Step 3 — Gap-step loop + real verifier integration

**Goal:** `k4k <file.k4k>` (no `--check`) runs the full convergence loop on a toy spec end-to-end. The integration test "echo CLI with `--upper`" goes from empty repo → green tests, driven by `Backend_stub` + real `dune` + `Verifier_dune_ocaml`.

**Modules created:** `lib/Gap_step` (one full iteration: select, prompt, diff, apply on scratch branch, verify, accept/reject); `lib/Verifier_dune_ocaml` (parse alcotest output per `external/dune.md`); risk-scoring inline in `Gap_step` (no separate module — see `spec/algorithms.md#risk-score`).

**Modules touched:** `lib/Harness` (gap-step loop), `lib/Persist` (add `gap/properties.json`, `agent-runs/`, `verifier-runs/` writers), `lib/Backend_stub` (add canned-patch mode), `lib/Backend_claude` (gap-step prompt support).

**Properties enforced (new):** P5 (non-regression on rejected patches), P6 (3-strikes-then-blocked), P9 (budget caps respected), P17 (no agent judgment on validity), NF1 (SIGINT ≤ 5 s), NF7 (audit-completeness via JSONL).

**Edge cases tested:** T3 (pre-existing partial implementation), T11 (verifier returns Unknown for all), T12 (3 failures → blocked + clarification), T14 (budget exhausted mid-step), T15 (SIGINT during agent call), T16 (SIGINT during verifier call), T20 (test name doesn't match convention).

**Acceptance tests:**
1. `S1_echo_first_run_e2e` — integration test: `tests/fixtures/echo-upper.k4k` → empty `examples/echo/` source dir → run k4k → final state has passing `dune runtest`. Driven by `Backend_stub` returning canned patches; verifier is real `dune`.
2. `P5_non_regression_under_rejected_patch` — establish two properties on a stub program; force agent to propose a regressive patch on the third; assert rejection.
3. `P6_three_strikes_then_blocked` — stub agent always proposes invalid patches; assert k4k blocks the property after exactly 3 attempts and appends a clarification.
4. `P9_hard_budget_cap_terminates_gracefully` — preset cumulative spend just below cap; trigger one more call; assert `EBUDGET` + consistent `.k4k/`.
5. `NF1_sigint_during_agent_exits_within_5s` — start k4k, send SIGINT during a stubbed-slow agent call, assert exit ≤ 5 s with no partial `agent-runs/<id>/`.
6. `T20_unconventional_test_name_warning` — verifier output contains a test not matching `P<id>_<slug>`; assert `verifier.warning` event + property mapped to `Unknown`.

**Definition of done:**
- All step-1 and step-2 acceptance still green.
- The S1 integration test runs in CI in < 3 minutes against `Backend_stub` (no live Claude).
- A live-mode smoke test runs the same scenario against real `Backend_claude` + real `dune` (gated by `K4K_LIVE=1`, not in CI).

---

## Step 4 — Polish: target-KB regeneration + TTY status + safety net

**Goal:** Every successful gap-step incrementally regenerates the target program's KB inside `.k4k/`. The TTY status line renders correctly. SIGINT/disk-full/concurrent-edit edge cases are handled. The remaining audit-checklist axes pass.

**Modules created:** `lib/Kb_regen` (incremental, ownership-aware target-KB regeneration); `lib/Logger.Tty_status` (in-place single-line TTY rendering, auto-disable on `!isatty(stdout)`).

**Modules touched:** `lib/Harness` (call `Kb_regen` after each successful gap-step; ETA model — sliding median); `lib/Persist` (target-KB file writes with `owner: k4k` frontmatter + content hash); `lib/Logger` (status line integration).

**Properties enforced (new):** P14 (ownership-flip detection on KB files), P16 (incremental, ownership-aware regeneration), P20 (`@invariant` annotations on every public function), NF2 (memory ceiling), NF3 (crash atomicity end-to-end), NF4 (state-confinement envelope), NF5 (secrets quarantine end-to-end).

**Edge cases tested:** T4 (user edits file mid-run), T5 (disk full), T8 (hand-edited `owner=k4k` region), T18 (user overrides a `k4k`-owned KB file), T19 (aspect maps to multiple properties).

**Acceptance tests:**
1. `P16_incremental_regen_only_touches_affected_files` — two-step run; assert only the affected target-KB files have new mtimes after the second step.
2. `P14_ownership_flip_on_user_edited_kb_file` — generate a target-KB file; user-edit it; re-run k4k; assert no regeneration + one `ownership.flip` event.
3. `NF2_rss_under_512mb_for_50_step_scenario` — synthetic 50-step scenario; sample RSS every 100 ms; assert max < 512 MB.
4. `NF5_secrets_canary_never_leaks` — set `ANTHROPIC_API_KEY=POISON-CANARY`; trigger every error path; grep all output streams + JSONL for `POISON-CANARY`; assert zero matches.
5. `T4_mid_run_edit_triggers_restability` — edit `<file.k4k>` between two gap-steps; assert next iteration's JSONL contains `stability.start`.
6. `T8_hand_edited_owner_k4k_section_flips_ownership` — modify bytes inside an `owner=k4k` block; re-run; assert hash mismatch detected, ownership flips, no overwrite.

**Definition of done:**
- All prior steps' acceptance still green.
- Phase 5 audit checklist passes on all 7 axes (`runbooks/audit-checklist.md`) with 0 criticals.
- A fresh integration scenario (`echo --upper` from the S1 test) leaves a complete target KB in `.k4k/` (`INDEX.md`, `GLOSSARY.md`, `spec/data-model.md`, etc.) — non-empty, frontmatter-valid, internally consistent.

---

## What this plan does NOT include (deferred, per `domain/prd.md#out-of-scope`)

- `Backend_ollama` — architecture is ready; implementation is v1+.
- Additional verifiers (Rocq, Frama-C, Verus, AFL).
- Additional program classes (`library`, `filter`, …).
- TUI dashboards, IDE integrations.
- Sandboxing of agent-written code (documented as user's responsibility).

## Step ordering rationale

Step 1 ships a running CLI before any agent call exists — that surfaces argv, parsing, error, and persistence bugs in isolation. Step 2 introduces stochasticity (the agent) before the gap-step loop adds *another* source of variability — debugging both at once is a known anti-pattern. Step 3 adds the loop and real verifier — the harness's headline feature. Step 4 is polish and safety net, including the target-KB regeneration that benefits every downstream user.

If step *N* fails to converge in 5 Ralph-Loop iterations, the slice is too large. Stop, return to this plan, and split.

## Plan-simulation gate

Before exiting Phase 3, a fresh subagent (KB-only access) walks each step end-to-end and reports any ambiguity. Output recorded as `kb/reports/plan-simulation-2026-05-02.md`. Resolved questions are reflected back into this plan; unresolved ones go to the user as round-3 questions.
