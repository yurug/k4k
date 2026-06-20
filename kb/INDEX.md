---
id: INDEX
type: index
summary: Master entry point for the k4k knowledge base. Always read this first.
domain: meta
last-updated: 2026-05-02
depends-on: []
refines: []
related: []
---

# k4k Knowledge Base — Master Index

## What this KB covers

`k4k` (KISS for KISS) builds **certified** POSIX-like programs. A software engineer writes and signs a *simple, formal-but-readable* specification in **k4kspec** (an observational spec language, ADR-015); k4k develops an implementation and a machine-checked proof that the implementation satisfies it, and ships a certificate that names exactly what is trusted (a TCB manifest). The agent *proposes* spec edits; the human is the sole committer of the spec (ADR-014). v1 pins one prover — Rocq + extraction to OCaml (ADR-016). This KB describes **k4k itself** — the tool — not the programs k4k builds (those have their own `.k4k/` KBs per ADR-006).

> **v3 reorientation (2026-06-19).** The KB was re-grounded on the certification thesis: see ADR-014/015/016, the rewritten `domain/prd.md`, and `reports/expert-panel-2026-06-19.md`. Files describing the v2 autonomous-daemon / cotype / single-file-edited-by-both design (ADR-010/011, `external/cotype.md`, much of `architecture/overview.md`, `spec/*`) are superseded or pending sync; trust the v3 ADRs + PRD where they conflict.

## How to use this KB (for agents)

**Always read first:**
1. `GLOSSARY.md` — canonical terms (no ambiguity downstream)
2. `domain/prd.md` — the v3 product (certification, persona, propose/review UX, tier model) — and the three ADRs it rests on: `architecture/decisions/adr-014`, `adr-015`, `adr-016`
3. `architecture/overview.md` — system shape (modules, DI, error hierarchy)

**Then route by task:** `indexes/by-task.md` is the navigation layer. Use it.

**For background only:**
- `NOTES.md` — the founding vision
- `archive/v0-drifted/` — historical Phase-1 artefacts and audit reports from the v0 build; useful for "why was decision X made and why did some choices later change?"

## Quick-load bundles

| Goal                                      | Load these files (in order)                                                                                      |
|-------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Implement a k4k feature                   | `INDEX.md` → `GLOSSARY.md` → `domain/prd.md` → `spec/algorithms.md` + relevant `spec/*` → `properties/functional.md` → `architecture/overview.md` → `conventions/code-style.md` |
| Add an agent backend (e.g. Ollama)        | `architecture/decisions/adr-009-backend-protocol.md` → `external/backend-protocol.md` → `examples/backends/claude-code/README.md` (worked example) → `conventions/context-economy.md` → `properties/non-functional.md#NF8` — **no k4k code change required** |
| Add a verifier (Rocq, Frama-C, Lean, Verus, …) | `architecture/decisions/adr-008-verifier-protocol.md` → `external/verifier-protocol.md` → the relevant `examples/verifiers/<x>/README.md` (Tier-A reference example forthcoming) → `domain/prd.md` (verification-tier model) — **no k4k code change required** |
| Run a quality audit                       | `runbooks/audit-checklist.md` → `properties/INDEX.md` → `conventions/testing-strategy.md`                       |
| Run weekly drift watch                    | `runbooks/drift-watch.md` → `external/*.md`                                                                       |
| Debug an issue                            | `spec/error-taxonomy.md` → `spec/algorithms.md` → `properties/edge-cases.md` → relevant `external/<sdk>.md`     |
| Write or fix tests                        | `conventions/testing-strategy.md` → `properties/INDEX.md` → `spec/api-contracts.md` → `external/verifier-protocol.md` |
| Author or modify a prompt                 | `conventions/context-economy.md` → `external/ollama.md` → `spec/algorithms.md` → `properties/functional.md`     |
| Understand a decision                     | `GLOSSARY.md` → `architecture/decisions/INDEX.md` → relevant ADR                                                |
| Understand the v0→v2 history              | `archive/v0-drifted/README.md`                                                                                  |
| Implement the v2 watcher / wrapper rewrite | `architecture/decisions/adr-011-autonomous-agent-ux.md` → `adr-012-agent-driven-toolchain.md` → `adr-013-version-as-git-branch.md` → `domain/prd.md` → `spec/config-and-formats.md` → `spec/algorithms.md` → `properties/functional.md#P21` `#P22` `#P23` |

## Top-level layout

```
kb/
├── INDEX.md                         this file
├── CLAUDE.md  (in repo root)        project-level instructions for Claude Code
├── GLOSSARY.md                      canonical terms
├── NOTES.md                         founding vision (kept for reference)
├── archive/v0-drifted/              historical Phase-1 artefacts + audit reports + v0 plan
│
├── domain/
│   └── prd.md                       v0 product scope, user stories, success criteria
│
├── spec/
│   ├── INDEX.md
│   ├── data-model.md                types: Property, Characterization, Manifest, ...
│   ├── config-and-formats.md        bytes on disk: .k4k file, .k4k/ tree, JSONL, atomicity
│   ├── algorithms.md                procedures: stability, formalization, gap-step, canonicalize, ...
│   ├── api-contracts.md             interfaces: CLI, agent backend, verifier
│   └── error-taxonomy.md            closed catalog of errors
│
├── properties/
│   ├── INDEX.md
│   ├── functional.md                P1..P20 — qualitative invariants
│   ├── non-functional.md            NF1..NF8 — measurable criteria
│   └── edge-cases.md                T1..T20 — boundary conditions
│
├── architecture/
│   ├── overview.md                  module structure, DI, error hierarchy
│   └── decisions/
│       ├── INDEX.md
│       ├── adr-001-ocaml-dune.md
│       ├── adr-002-interaction-file-format.md
│       ├── adr-003-pluggable-backend.md
│       ├── adr-004-verifier-extension.md
│       ├── adr-005-canonical-ast.md
│       ├── adr-006-two-layer-kb.md
│       ├── adr-007-deterministic-kb-regen.md
│       ├── adr-008-verifier-protocol.md
│       ├── adr-009-backend-protocol.md
│       ├── adr-010-cotype-delegation.md
│       ├── adr-011-autonomous-agent-ux.md
│       ├── adr-012-agent-driven-toolchain.md
│       └── adr-013-version-as-git-branch.md
│
├── external/
│   ├── INDEX.md
│   ├── backend-protocol.md          wire protocol any agent backend must implement (ADR-009)
│   ├── verifier-protocol.md         wire protocol any verifier executable must implement (ADR-008)
│   ├── cotype.md                    hardcoded runtime dep for interaction-file concurrency (ADR-010)
│   └── ollama.md                    architectural guidance for weakness-profile prompt design
│
├── conventions/
│   ├── code-style.md                OCaml rules, file/function caps, doc-comments
│   ├── error-handling.md            typed hierarchy, scrubbing, retries
│   ├── testing-strategy.md          test naming, four kinds, coverage
│   └── context-economy.md           prompt design for the weakest supported backend
│
├── runbooks/
│   ├── audit-checklist.md           Phase-5 quality audit checklist (7 axes)
│   ├── test-environment.md          test-only K4K_* env knobs (closed set, default-OFF)
│   └── drift-watch.md               weekly maintenance: protocol-conformance + dep-version drift
│
├── indexes/
│   └── by-task.md                   primary navigation: "I need to do X → load A, B, C"
│
└── reports/                         (empty until first audit)
```

## File count and last updated

- **Methodology files**: 40 (+ ADR-011, ADR-012, ADR-013)
- **Reference files** active: `NOTES.md`. Archived under `archive/v0-drifted/`: questions-round{1,2,3}, plan, plan-simulation report, all audit reports, the user's feedback that triggered the v2 reorientation.
- **Last updated**: 2026-05-03

## Methodology phase tracker

| Phase | State                                                    |
|-------|----------------------------------------------------------|
| 1 — Ambiguity resolution                                  | ✓ done (rounds 1, 2, 3)         |
| 2 — KB construction                                       | ✓ done                          |
| 2k — KB audit (Ralph Loop + KB-quiz)                      | ✓ done (10/10 quiz, 0 criticals)|
| 3 — Plan + simulation gate                                | ✓ done (archived as `archive/v0-drifted/plan.md` after v2 reorientation) |
| 4 — Implement (Ralph Loops, per step)                     | ✓ done (steps 1–4)              |
| 5 — Quality audits                                        | ✓ done — skeptical second pass found 2 criticals + 7 highs the dry-pass missed; all closed (`archive/v0-drifted/audit-real-2026-05-02.md`) |
| 6 — KB sync                                               | ✓ done (ADR-007, env-var runbook, alcotest fact, T1 note; sync-quiz 3/3) |
| 7 — Documentation & validation                            | ✓ done (README.md; e2e validation green from clean tempdir) |
| v1 — ADR-008 verifier-protocol retrofit                   | ✓ done (`lib/Verifier_external` + `examples/verifiers/dune-ocaml/`) |
| v1 — ADR-009 backend-protocol retrofit                    | ✓ done (`lib/Backend_external` + `examples/backends/claude-code/`) |
| v1 — Reference Ollama backend                             | ✓ done (`examples/backends/ollama/`; live-verified against `qwen3.5:9b`) |
| v1 — ADR-010 cotype delegation                            | ✓ done (`lib/cotype.ml` + `lib/cotype_stub.ml` + `lib/clarification.ml`; `lib/persist_lock.ml` removed; live cotype 0.2.3 verified) |
| v1 — Protocol-conformance suite + drift-watch             | ✓ done (`test/conformance/` 6 tests; `kb/runbooks/drift-watch.md`; baseline at `kb/reports/dep-versions-baseline.txt`) |
| **v2 reorientation** — UX is autonomous agent, not developer CLI; default tier is Tier-A formal verification | KB cleanup ✓; round-4 + round-5 questions ✓; ADR-011 / ADR-012 / ADR-013 ✓; engine extensions (`lib/Toolchain_install`, `lib/Version`, `Characterization` extended) ✓; **code rewrite ✓** (`bin/main.ml` is the watcher daemon; `lib/Watcher`/`Watcher_loop`/`Watcher_pid` orchestrate; `lib/Inline_blocks`/`Status_splice`/`Starter_template` handle the in-file surface; tier-aware prompts at `prompts/gap-step.tier-{a,b,c}.md`; `examples/verifiers/dune-ocaml/` removed; conformance suite uses `test/conformance/fixtures/synthetic-verifier.sh`) |
| **v2 batch 3** — wire watcher to gap-step engine + Version state machine | ✓ done (`lib/Audit_md`, `lib/Version_persist`, `lib/Version_loop`, `lib/Watcher_dev`; watcher cuts a `k4k/version/<n>` branch on stability, drives an accept-only gap loop emitting `[k4k] establish <pid>` commits, merges + tags + deletes the branch on completion, renders `audit.md`; `--exit-on-done` flag for tests; S1 + S5 integration tests drive the full lifecycle; 236 tests green). Marker-file mock for the gap-step body (replaced in 4a). |
| **v2 batch 4a** — direct-commit gap-step on the version branch (ADR-013 §2 step 3 reconciliation) | ✓ done. `lib/Gap_step` rewritten: no more `k4k/gap/<id>/<ts>` scratch branches — diffs apply directly to the working tree on `k4k/version/<n>`, accepted steps commit via `Version.commit_accept`, rejected steps `git reset --hard HEAD`. New outcome variant `Tradeoff` placeholder for batch-4b. New modules: `lib/Backend_canned` (test-only canned-response loader for `K4K_STUB_RESPONSES`), `lib/Version_finalize` (audit / merge / tag extracted from `Version_loop`). New `Git.reset_hard`. `lib/Gap_branch` deleted. Watcher_dev now wires real backend + verifier closures into `Version_loop`. S1 integration test asserts on real source files landing on `main`. 217 unit + 13 integration + 6 conformance + 4 edge = 240 tests green. Deferred to batch 4b: tradeoff-proposal authoring (currently `Tradeoff` is a placeholder treated as deferred), real formalization replacing `K4K_TEST_D_PATH`, clarification pruning, welcome auto-delete. |
| **v2 batch 4b** — tradeoff state machine + pruning + welcome auto-delete | ✓ done. `lib/Tradeoff_flow` (proposal splice, polling, archive+breadcrumb), `lib/Version_tradeoff` (per-version tradeoff tracking + drive-at-tier dispatch + post-approval Tier-B/C execution), `lib/Watcher_prune` (welcome auto-delete + clarification/tradeoff archival), `lib/Inline_blocks_sections` (section-aware splice). Post-approval execution wires `Tradeoff_flow.propose_and_wait`'s file-mutation residue (proposal splice + breadcrumb) into a version-branch commit (`[k4k] tradeoff <label>: <pid>`) before re-entering `Gap_step.step` at the approved tier — `Gap_step.preflight` requires a clean tree. S3 integration test asserts on `version.commit` post-approval at `tier=B`. Test count: 238 unit + 14 integration + 6 conformance + 4 edge = 262 tests green. **Deferred:** P22 user-edits-during-development queueing. |
| **v2 batch 4c** — P22 user-edits-during-development queueing | ✓ done. `lib/Version_user_edits` snapshots user-section hashes at version start and (between gap-step iterations in `Version_loop.run_gap_loop`) detects drift, splices an updated `## k4k:status` block carrying the new `pending_user_edits` count, commits the residue (`[k4k] queue user edits for v<n+1> (<count> section(s))`), and emits a `user_edits.queued` JSONL event. A `surfaced` ref deduplicates so a single edit produces exactly one event. Parser bug fix: `Parser_sections` now treats every `k4k-*`-prefixed id as k4k-managed (was: only `k4k-clarification`); the prior version mis-classified `k4k:status`/`k4k:version`/`k4k:tradeoff:proposal:*`/`k4k:welcome` as user-owned, which made every status-block timestamp splice look like a user edit. P22 integration test exercises the full path: a verifier wrapper writes a sentinel into the `## Goal` section on its first call, the watcher detects drift, surfaces it once, completes the version, and the user's edit lands on `main` via the merge. Test count: 243 unit + 15 integration + 6 conformance + 4 edge = 268 tests green. |
| **v2 batches 5–17** — multi-version cycle + Phase-5 audit + closure | ✓ done. Batch 5 added `--max-versions=N` + the idempotence gate (`last_completed_d_hash`) + the `claude-code` wire-mock + the README sync. Batch 6 ran a 7-axis Phase-5 audit (`kb/reports/audit-2026-05-08-*`); 3 critical, 11 high, 16 medium, 17 low. Batches 6-17 closed all criticals + all highs (including the load-bearing `Git.apply_diff` path-filter, the `Backend_external` production wiring via `K4K_BACKEND_COMMAND` + `lib/Backend_resolve`, the orphan-module deletion of `Run_loop`/`Harness`/`Full_check`, the spec-docs sync to ADR-011/012/013, the closed-error-catalog hardening with `E_ownership_violation` + `E_internal_panic`, the architecture/overview rewrite, the `Property.blocked` cleanup, and 8 focused unit tests for `Manifest` / `Version_finalize` / `Tradeoff_flow` / `Watcher.startup`). Batch 17 ported NF2/4/6/7 onto the v2 `Version_loop` path (lost when batch 7 deleted the v0 chain) and closed the deferred T2 + T15 tests. Final test count: 262 unit + 23 integration + 6 conformance + 4 edge = **295 tests green**. The audit-2026-05-08 closure summary is at `kb/reports/audit-2026-05-08-summary.md`. |
| **v3 reorientation** — certification tool; k4kspec spec language; propose/review UX; pinned Rocq+extraction | KB ✓ (2026-06-19): ADR-014 (certification + propose/review, supersedes ADR-010/011), ADR-015 (k4kspec observational language, demotes ADR-005), ADR-016 (v1 verification model + 10-expert-panel refinements, revises ADR-012); PRD rewritten; GLOSSARY v3 terms; panel report at `kb/reports/expert-panel-2026-06-19.md`. **Code: not started** — surface to be rebuilt around the kept harness core; cotype layer + in-file orchestration to be removed. **Open design:** spec-language semantics (relation forms; value algebra incl. lambdas-vs-combinators; fs-effect model), the executable spec-validation phase, the statement-preserving elaborator. |
| **v3 design pass** (2026-06-20) — spec-language semantics + guidance doc + intent UX | KB ✓: ADR-017 (guidance document — third, uncertified artifact); `spec/k4kspec.md` (language reference — semantic domain, relation R, surface forms, value algebra incl. opinion-free principle + lambdas-as-combinator-args, fs frame/footprint incl. variadic + deletion, under-spec posture, worked examples grepf/cutf/catf); ADR-014 += intent-seeded generation + decision-focused review; ADR-016 += clone-as-oracle, under-spec sign-off, certificate-scope disclosure, NFR triage. **Still open:** blessed-def precise semantics, the I/O shim (cli×Rocq), the IR + statement-preserving elaborator, the validation oracle, argv-grammar sugar. |
| **v3 BUILD** (2026-06-20) — validation front-end + REALIZED v1 certify back-end | Code ✓ in `k4kspec/` (stdlib-only OCaml; separate from the v2 tree). Front-end: parser (`lib/parse.ml`, round-trip tested) + the reference-free validation harness (oracle/examples/stability/curated sweep). **Back-end (ADR-018):** `k4kspec certify <file>` = elaborate (`lib/rocq_emit.ml`) → coqc-checked proof → extract → compile(+shim) → run → cross-check vs oracle → TCB manifest. **All 6 v1-fragment specs certify** (upper/greet/grepf/kvget/cutf/catf), each FRESH-AGENT audited GREEN with tamper tests (non-vacuous). Blessed algebra audited-once (`backend/Kalgebra.v`). Commits 0f9eb9d..63ee151. **Honest limit:** v1 generates `run` to match the spec ⇒ easy proofs (certifies the pipeline, not hard-proof automation). **Next:** the agent proof backend (ADR-019, the central bet); statement-preserving elaborator; verified extraction. |
| **v3 AGENT-PROOF** (2026-06-20) — the central bet, realized + validated + given a methodology | **ADR-019:** `certify-agent <file>` — elaborator fixes `spec_rel`; an external agent (`$K4K_PROOF_CMD`, e.g. tools-off `claude -p`) proposes `run`+proof; coqc is the only gate (+ error-feedback retries, fresh-agent audited GREEN; can't be tricked by a `spec_rel` redefinition). Relational-LAWS machinery (output-refs + per-case `laws` + under-determined channels; `Sorted`/`Permutation`/`ascii_le`/`part_le`/`ascii_lt` in Kalgebra). **Validated:** easy (`upper`+4 pinned), HARD inductive (`bsort`: invented insertion sort, proved Sorted/Permutation), HARD non-sort (`partition`: custom preorder, proof by construction). **Ceiling found:** `usort` (strict-sort + set-equality, multi-invariant) — one-shot monolithic generation stalls. **ADR-020 (methodology):** replace one-shot with **implement-naive → SKETCH (kernel-checked skeleton gate: lemmas Admitted, coqc verifies the decomposition suffices) → fill each lemma in isolation → assemble + no-admits gate.** Correctness-only for v1. Commits 63ee151..c118155 (+ methodology build next). |

## Agent notes

> **Self-sufficient files.** Every file in this KB stands alone given `GLOSSARY.md`. If you read a file and it does not make sense without context from elsewhere, that is a bug — fix the file or its glossary entries before consuming the content.
>
> **Two-layer KB.** This KB describes k4k itself. The `.k4k/` directory in any target project describes *that project's program*. They share a layout (per ADR-006) but are different KBs. Don't mix.
