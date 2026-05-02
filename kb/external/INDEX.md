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

## Routing table

| If you need...                                        | Read this file              | Key questions answered                                                  |
|-------------------------------------------------------|-----------------------------|-------------------------------------------------------------------------|
| The v0 agent backend (Claude Code headless)           | `claude-code.md`            | How is `claude -p` invoked? What's the JSON output shape? Failure modes? |
| The v0 verifier (dune)                                | `dune.md`                   | What invocation flags? How is alcotest output parsed? Exit-code semantics? |
| The v1+ Ollama target — design constraints in v0      | `ollama.md`                 | What capability budget do prompts target? Why does this matter for v0?    |

## Files

- `claude-code.md` — invocation, output, budget, failure modes, sandboxing
- `dune.md` — `@check` vs `@runtest`, parsing alcotest output, the `P<id>_<slug>` test-name convention
- `ollama.md` — v1+ target, design constraints applied in v0 via `Backend_stub`

## Reading order

`claude-code.md` and `dune.md` first (v0 actually depends on these). `ollama.md` last (informs the design but is not yet a dependency).
