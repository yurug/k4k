---
id: external.ollama
type: external
summary: v1+ target for local LLM agent backend. Captured now (v0) so prompts and the agent-backend abstraction are designed against this constraint, not against Claude.
domain: external
last-updated: 2026-05-02
depends-on: [glossary, spec.api-contracts]
refines: []
related: [adr-003, conventions.context-economy, properties.non-functional]
---

# External: Ollama (local LLM, v1+ target)

## One-liner

A local HTTP server hosting open-weight models (default `http://localhost:11434`). v0 does **not** ship Ollama support, but this file documents it so prompts and the backend abstraction are designed for it from day one (per ADR-003 and `NF8`).

## Scope

What we *will* depend on. Captures the constraints the v0 prompt/budget design must respect — not an implementation guide.

## Why this file exists in v0

Per round-2 user-added: "agents will need to be provided very optimized contexts because they are not as good as Claude (with Opus)". Designing now is much cheaper than retrofitting. v0 ships `Backend_stub` with an Ollama-shaped capability profile so prompts are exercised against the weakness target before any real Ollama integration ships.

## Likely invocation surface (v1)

Ollama exposes an HTTP API:
- `POST /api/generate` — single completion, optional streaming.
- `POST /api/chat` — chat-style messaging.
- `GET /api/tags` — list installed models.

A v1 `Backend_ollama` will use `/api/generate` with `stream:false` for symmetry with the v0 subprocess model.

## Default behavior (no auth)

- No authentication on the local socket. Trust model: same machine = trusted.
- For non-localhost deployment, k4k must require a TLS tunnel + bearer token; v1 ADR will document.

## Capability profile we design against

Working assumption: `codellama:7b-instruct` or similar 7B-class model.

| Dimension                  | Assumption                                                            |
|----------------------------|-----------------------------------------------------------------------|
| Context window             | 8k tokens (model-dependent — be conservative)                         |
| Effective reasoning depth  | Shallow; chain-of-thought beyond ~3 steps degrades                    |
| JSON-output reliability    | Good for trivial schemas; brittle for nested or many-field schemas    |
| Tool-use protocols         | None (no MCP; no native tool calls). All "tools" must be parsed out of free text |
| Latency                    | 1-10 s for 1k-token completions on consumer GPU; 10-60 s on CPU       |

These constraints set hard upper bounds on every prompt template. See `conventions/context-economy.md`.

## Implications for prompt design

- **Prompts ≤ ~3k tokens of input.** Leave ~1k for completion within an 8k window.
- **JSON schemas in prompts must be flat.** Nested objects degrade reliability sharply on small models.
- **One task per prompt.** No "do this, then also do that". Multi-step tasks must be decomposed into multiple `invoke` calls.
- **No reliance on the model's "judgment".** Already an architectural constraint (`P17`) — the local-LLM target reinforces it.
- **Concrete examples > abstract instructions.** Few-shot beats zero-shot at this scale.

## Implications for output parsing

- The harness must tolerate sloppy JSON: trailing commas, occasional wrapping prose. We strip Markdown code fences and run a permissive JSON parse before strict validation.
- The two-run protocol of ADR-005 is *more* important here, not less — small models are more variable.

## Failure modes (anticipated)

| Failure                                  | Detection                                | k4k action                                  |
|------------------------------------------|------------------------------------------|---------------------------------------------|
| Ollama daemon not running                | TCP connect refused on port 11434        | `EAGENT_UNAVAILABLE`                         |
| Model not pulled                         | `/api/generate` returns 404 with model name | `EAGENT_UNAVAILABLE` with hint              |
| Context overflow                         | Output truncated; final tokens missing   | Mark response invalid; retry with shorter prompt; eventually unstable |
| Non-JSON output when JSON requested      | Parse failure                            | Retry once with stricter formatting; then reject |

## Cost model

Ollama has no monetary cost; the constraint is wall-clock and GPU/CPU contention. The v1 budget unit will likely re-define as "wall-clock seconds equivalent" with a per-call cap.

## Status

- **Not implemented in v0.** No `Backend_ollama` module exists.
- **Designed against in v0** via `Backend_stub`'s "weak" capability profile in CI.
- **Promoted to v1** with its own ADR upon implementation.

## Agent notes

> **The litmus test:** if a prompt only works on Claude, it's a bug now (in v0), not a v1 polish item. Run it through `Backend_stub`'s weak profile or against a local Ollama instance manually before merging.
>
> **Don't add Ollama support to v0** even if it would be easy — staying narrow is part of the methodology. ADR-003 codifies the abstraction; the implementation is for v1.

## Related files

- `architecture/decisions/adr-003-pluggable-backend.md` — the design decision this file informs
- `conventions/context-economy.md` — concrete prompt-design rules
- `properties/non-functional.md#NF8` — the invariant that makes this file load-bearing
