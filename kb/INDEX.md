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

`k4k` (KISS for KISS) is a deterministic harness that drives a coding agent to build POSIX-like CLI programs from an interaction file, accepting only patches a verifier validates against a formal characterization. This KB describes **k4k itself** — the tool — not the programs k4k builds (those have their own `.k4k/` KBs per ADR-006).

## How to use this KB (for agents)

**Always read first:**
1. `GLOSSARY.md` — canonical terms (no ambiguity downstream)
2. `architecture/overview.md` — system shape (modules, DI, error hierarchy)
3. `domain/prd.md` — what's in scope for v0

**Then route by task:** `indexes/by-task.md` is the navigation layer. Use it.

**For background only:**
- `NOTES.md` — the founding vision (informational; superseded by `domain/prd.md` for scope)
- `questions-round1.md`, `questions-round2.md` — Phase 1 artefacts; useful for "why was decision X made?"

## Quick-load bundles

| Goal                                      | Load these files (in order)                                                                                      |
|-------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Implement a k4k feature                   | `INDEX.md` → `GLOSSARY.md` → `domain/prd.md` → `kb/plan.md` (Phase 3) → `spec/algorithms.md` + relevant spec/ → `properties/functional.md` → `architecture/overview.md` → `conventions/code-style.md` |
| Add an agent backend (e.g. Ollama)        | `architecture/decisions/adr-003-pluggable-backend.md` → `spec/api-contracts.md#agent-backend` → `external/ollama.md` (or write your own) → `conventions/context-economy.md` → `properties/non-functional.md#NF8` |
| Add a verifier (e.g. Rocq)                | `architecture/decisions/adr-004-verifier-extension.md` → `spec/api-contracts.md#verifier` → `external/dune.md` (model your adapter on it) |
| Run a Phase-5 audit                       | `runbooks/audit-checklist.md` → `properties/INDEX.md` → `conventions/testing-strategy.md`                       |
| Debug an issue                            | `spec/error-taxonomy.md` → `spec/algorithms.md` → `properties/edge-cases.md` → relevant `external/<sdk>.md`     |
| Write or fix tests                        | `conventions/testing-strategy.md` → `properties/INDEX.md` → `spec/api-contracts.md` → `external/dune.md`        |
| Author or modify a prompt                 | `conventions/context-economy.md` → `external/ollama.md` → `spec/algorithms.md` → `properties/functional.md`     |
| Understand a decision                     | `GLOSSARY.md` → `architecture/decisions/INDEX.md` → relevant ADR                                                |

## Top-level layout

```
kb/
├── INDEX.md                         this file
├── CLAUDE.md  (in repo root)        project-level instructions for Claude Code
├── GLOSSARY.md                      canonical terms
├── NOTES.md                         founding vision (kept for reference)
├── questions-round{1,2}.md          Phase 1 artefacts
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
│       └── adr-006-two-layer-kb.md
│
├── external/
│   ├── INDEX.md
│   ├── claude-code.md               v0 agent backend — runtime behavior, budget, failure modes
│   ├── dune.md                      v0 verifier — invocation, parsing, exit codes
│   └── ollama.md                    v1+ target — design constraints applied in v0
│
├── conventions/
│   ├── code-style.md                OCaml rules, file/function caps, doc-comments
│   ├── error-handling.md            typed hierarchy, scrubbing, retries
│   ├── testing-strategy.md          test naming, four kinds, coverage
│   └── context-economy.md           prompt design for the weakest supported backend
│
├── runbooks/
│   └── audit-checklist.md           Phase-5 quality audit checklist (7 axes)
│
├── indexes/
│   └── by-task.md                   primary navigation: "I need to do X → load A, B, C"
│
└── reports/                         (empty until first audit)
```

## File count and last updated

- **Methodology files**: 30
- **Reference files** (NOTES, claude-code-report, opencode, questions-round{1,2}): 5
- **Last updated**: 2026-05-02

## Methodology phase tracker

| Phase | State                                                    |
|-------|----------------------------------------------------------|
| 1 — Ambiguity resolution                                  | ✓ done (rounds 1, 2, 3)         |
| 2 — KB construction                                       | ✓ done                          |
| 2k — KB audit (Ralph Loop + KB-quiz)                      | ✓ done (10/10 quiz, 0 criticals)|
| 3 — Plan (`kb/plan.md`) + simulation gate                 | ✓ done                          |
| 4 — Implement (Ralph Loops, per step)                     | steps 1–3 ✓ ; step 4 pending    |
| 5 — Quality audits                                        | not started                      |
| 6 — KB sync                                               | not started                      |
| 7 — Documentation & validation                            | not started                      |

## Agent notes

> **Self-sufficient files.** Every file in this KB stands alone given `GLOSSARY.md`. If you read a file and it does not make sense without context from elsewhere, that is a bug — fix the file or its glossary entries before consuming the content.
>
> **Two-layer KB.** This KB describes k4k itself. The `.k4k/` directory in any target project describes *that project's program*. They share a layout (per ADR-006) but are different KBs. Don't mix.
