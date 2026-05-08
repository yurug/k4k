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

`k4k` (KISS for KISS) is an autonomous coding agent that builds **formally verified** POSIX-like programs from a single user-edited file. The user writes free-form prose; k4k watches the file, asks clarifying questions in-line until the spec denotes a clear theorem, then develops + verifies in full autonomy with full formal verification by default (Rocq+Extraction, Frama-C, Lean, Verus, F*). This KB describes **k4k itself** — the tool — not the programs k4k builds (those have their own `.k4k/` KBs per ADR-006).

## How to use this KB (for agents)

**Always read first:**
1. `GLOSSARY.md` — canonical terms (no ambiguity downstream)
2. `domain/prd.md` — the user-facing UX and verification-tier model (post-v2-reorientation)
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
| **v2 batch 3** — wire watcher to gap-step engine + Version state machine | ✓ done (`lib/Audit_md`, `lib/Version_persist`, `lib/Version_loop`, `lib/Watcher_dev`; watcher cuts a `k4k/version/<n>` branch on stability, drives an accept-only gap loop emitting `[k4k] establish <pid>` commits, merges + tags + deletes the branch on completion, renders `audit.md`; `--exit-on-done` flag for tests; S1 + S5 integration tests drive the full lifecycle; 236 tests green). Limitations: real formalization (Convergence wiring) deferred to batch 4 — under the new `K4K_TEST_D_PATH` knob the test path is fully exercised; tradeoff-proposal authoring + clarification pruning + welcome auto-delete are deferred. |

## Agent notes

> **Self-sufficient files.** Every file in this KB stands alone given `GLOSSARY.md`. If you read a file and it does not make sense without context from elsewhere, that is a bug — fix the file or its glossary entries before consuming the content.
>
> **Two-layer KB.** This KB describes k4k itself. The `.k4k/` directory in any target project describes *that project's program*. They share a layout (per ADR-006) but are different KBs. Don't mix.
