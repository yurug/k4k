---
id: spec.index
type: index
summary: Routing table for the spec layer — types, formats, algorithms, contracts, errors.
domain: spec
last-updated: 2026-05-02
depends-on: []
refines: []
related: [domain.prd, properties.index, architecture.overview]
---

# Spec — Routing Table

## How to use this index

If you are about to write code, modify a procedure, or change a data shape, find your concern below and read the linked file in isolation. Each spec file is self-sufficient given `GLOSSARY.md`.

## Routing table

| If you need...                                                  | Read this file                  | Key questions answered                                                                                |
|-----------------------------------------------------------------|---------------------------------|--------------------------------------------------------------------------------------------------------|
| The shape of any persistent or in-memory entity                | `data-model.md`                | What fields does a Property have? What is in a Manifest? What is the `cli` coverage checklist?         |
| The bytes on disk for any file k4k reads or writes             | `config-and-formats.md`        | What does a `.k4k` file look like? How is `.k4k/manifest.json` laid out? What's the JSONL log format? |
| Any procedure k4k runs                                         | `algorithms.md`                | How does the stability check work? How is the gap built? How is the next property chosen?              |
| The interface to the agent backend or verifier                 | `api-contracts.md`             | What signatures must a backend satisfy? What does the public CLI commit to?                           |
| The exit codes and error catalog                               | `error-taxonomy.md`            | Which error has which exit code? What does the user see for `EUNSTABLE`?                              |

## Reading order for new contributors

1. `GLOSSARY.md` — terms
2. `data-model.md` — types
3. `config-and-formats.md` — bytes
4. `algorithms.md` — procedures
5. `api-contracts.md` — interfaces
6. `error-taxonomy.md` — errors

## Files

- `data-model.md` (Property, Characterization, Manifest, AgentRun, VerifierRun, coverage checklist)
- `config-and-formats.md` (interaction file, `.k4k/` tree, atomic writes, locking, JSONL)
- `algorithms.md` (stability, formalization, canonicalization, risk-score, gap-step, KB regen, ownership)
- `api-contracts.md` (CLI contract, agent-backend signature, verifier signature, internal contracts)
- `error-taxonomy.md` (every error id, exit code, message, recovery)
