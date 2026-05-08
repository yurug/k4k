---
id: external.index
type: index
summary: Routing table for external dependencies — actual runtime behavior and request budgets per integration.
domain: external
last-updated: 2026-05-03
depends-on: []
refines: []
related: [spec.api-contracts]
---

# External Dependencies — Routing Table

## Why this layer exists

Per the agentic-dev-kit methodology: third-party SDKs and CLIs are the most common source of architectural surprises. Every dependency gets a file documenting its **actual runtime behavior** (not its public API), with a **request budget** computed against k4k's expected workload.

After ADR-008 (verifier-protocol retrofit) and ADR-009 (backend-protocol retrofit), k4k carries no tool-specific dependencies in `lib/`. Tool-side runtime details live with each external executable; only the **wire protocols** are documented here.

## Routing table

| If you need...                                                         | Read this file              | Key questions answered                                                  |
|------------------------------------------------------------------------|-----------------------------|-------------------------------------------------------------------------|
| The wire protocol any agent backend must implement                     | `backend-protocol.md`       | What command-line shape? What JSON result schema? Exit codes? Budgets?  |
| The wire protocol any verifier must implement                          | `verifier-protocol.md`      | What command-line shape? What JSON result schema? Exit codes?           |
| The runtime contract for cotype (interaction-file concurrency dep)     | `cotype.md`                 | What CLI commands does k4k call? What exit codes? When does it conflict? |
| The toolchain-install registry (ADR-012)                                | `toolchain-install.md`      | Which binary names map to which user-scoped package managers? When does k4k auto-install vs prompt? |
| Architectural guidance for backends targeting weak local models        | `ollama.md`                 | What capability budget do prompts target? Why does this matter?         |

## Files

- `backend-protocol.md` — the agent-backend wire protocol (ADR-009)
- `verifier-protocol.md` — the verifier wire protocol (ADR-008)
- `cotype.md` — runtime contract for the cotype CLI (interaction-file concurrency dep, ADR-010)
- `toolchain-install.md` — registry of binary→user-scoped-package-manager mappings (ADR-012)
- `ollama.md` — architectural guidance for prompt design under the weakness profile

## Reading order

`backend-protocol.md` and `verifier-protocol.md` first (k4k's actual external surfaces). `ollama.md` last (informs the prompt-design constraints in `conventions/context-economy.md`).

## Per-tool docs (not in `kb/external/`)

Tool-specific runtime details live alongside each example executable, not in `kb/`. See `examples/backends/claude-code/README.md` for the reference Claude Code backend, and `examples/verifiers/dune-ocaml/README.md` for the reference OCaml/dune verifier.
