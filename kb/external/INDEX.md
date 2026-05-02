---
id: external.index
type: index
summary: Routing table for external dependencies — actual runtime behavior and request budgets per integration.
domain: external
last-updated: 2026-05-02
depends-on: []
refines: []
related: [spec.api-contracts]
---

# External Dependencies — Routing Table

## Why this layer exists

Per the agentic-dev-kit methodology: third-party SDKs and CLIs are the most common source of architectural surprises. Every dependency gets a file documenting its **actual runtime behavior** (not its public API), with a **request budget** computed against k4k's expected workload.

After ADR-008 (verifier-protocol retrofit), k4k carries no verifier-specific dependency. Verifier-side runtime details live with each verifier executable; only the **wire protocol** is documented here.

## Routing table

| If you need...                                                         | Read this file              | Key questions answered                                                  |
|------------------------------------------------------------------------|-----------------------------|-------------------------------------------------------------------------|
| The agent backend (Claude Code headless)                               | `claude-code.md`            | How is `claude -p` invoked? What's the JSON output shape? Failure modes? |
| The wire protocol any verifier must implement                          | `verifier-protocol.md`      | What command-line shape? What JSON result schema? Exit codes?           |
| The v1+ Ollama target — design constraints in v0                       | `ollama.md`                 | What capability budget do prompts target? Why does this matter for v0?  |

## Files

- `claude-code.md` — invocation, output, budget, failure modes, sandboxing
- `verifier-protocol.md` — the verifier wire protocol (replaces the v0 `dune.md`; per ADR-008)
- `ollama.md` — v1+ target, design constraints applied in v0 via `Backend_stub`

## Reading order

`claude-code.md` and `verifier-protocol.md` first (k4k's actual external surfaces). `ollama.md` last (informs the design but is not yet a dependency).

## Per-verifier docs (not in `kb/external/`)

Verifier-specific runtime details (e.g. how the dune-ocaml example parses alcotest output) live alongside each verifier executable, not in `kb/`. See `examples/verifiers/dune-ocaml/README.md` for the reference implementation.
