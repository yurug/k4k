---
id: adr-003
type: decision
summary: Agent backends are pluggable via an OCaml module signature; v0 ships claude-code, but every prompt is designed against the weakest supported backend (target Ollama 7B-class).
domain: architecture
last-updated: 2026-05-02
depends-on: [domain.prd, spec.api-contracts]
refines: []
related: [adr-005, conventions.context-economy, external.claude-code, external.ollama, properties.non-functional]
---

# ADR-003: Pluggable agent backend; design for the weakest supported model

## Status
Accepted (2026-05-02). **Partially superseded by ADR-009** (2026-05-03): the *pluggable* claim and the *weakness-profile prompt-design discipline* both stand; the *plug shape* moved from "OCaml module signature, one adapter per tool" to "wire protocol over JSON files, one generic adapter". The Claude-Code-specific reasoning below applies to the *example backend* now shipped at `examples/backends/claude-code/`, not to a built-in module.

## Context
The user (round 2 user-added) explicitly requested: support for local LLMs via Ollama as a future backend, with the consequence that prompts must be optimized for weak local models because they are less capable than Claude Opus.

If we instead designed prompts against Claude only:
- Switching to Ollama later would require re-engineering every prompt.
- The harness's behavior would silently change (Ollama might fail at canonicalization tasks Claude handles fine).
- The user's auditability promise would fragment per-backend.

We need a design that survives the switch.

## Decision
1. **The agent backend is an OCaml module signature** (`Agent_backend` in `spec/api-contracts.md`). The harness depends only on this signature.
2. **v0 ships exactly one implementation: `claude-code`** (subprocess invocation; see `external/claude-code.md`).
3. **A test-only `Backend_stub` is shipped from day one** with a configurable "weakness profile" — token-limited responses, refusal-to-reason hooks, deliberate stochasticity. Used in CI to ensure prompts work on weak backends.
4. **Every prompt template** in `prompts/` is authored against an explicit *capability budget* defined in `conventions/context-economy.md`: max ~4k tokens of context, no nested reasoning beyond what a 7B-class model can do reliably, JSON output schemas trivially extractable.
5. **Future: `Backend_ollama`** ships in v1. Its addition must be a pure additive change — no harness modifications.

## Consequences
- v0 ships with a single live backend, but the architecture is genuinely portable.
- Prompts may underperform on Claude relative to what Claude *could* do — accepted, because the alternative is brittle scale-up.
- The `Backend_stub` weakness-profile harness is itself a non-trivial v0 deliverable; it pays for itself by making the test suite robust to backend variance.
- Cost: prompt engineering takes longer (must be tested against the stub); benefit: zero retrofit cost when Ollama lands.

## What this means for implementers
- **Never feature-detect on `Agent_backend.name`.** If you need different behavior per backend, the abstraction is wrong; fix it via the signature.
- **Author prompts in `prompts/<name>.md`** as plain text with `{{var}}` placeholders. Lint check: token count + presence of "let me think step by step" anti-patterns.
- **Run the stub's weak profile in CI** for every PR that touches a prompt.
- **`Backend_claude` invocation is via subprocess** (`claude -p ...`); see `external/claude-code.md`. No SDK dependency in v0.
