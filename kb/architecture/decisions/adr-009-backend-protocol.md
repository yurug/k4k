---
id: adr-009
type: decision
summary: k4k carries zero backend-specific code. Backends are external executables conforming to a documented wire protocol; k4k ships one generic adapter (Backend_external) and a stub. Symmetric to ADR-008 for verifiers.
domain: architecture
last-updated: 2026-05-03
depends-on: [adr-003, adr-008, glossary, spec.api-contracts]
refines: [adr-003]
related: [external.backend-protocol]
---

# ADR-009: Wire-protocol backend; k4k ships no backend-specific code

## Status
Accepted (2026-05-03). Supersedes the v0-only narrowing in ADR-003 ("v0 ships exactly one implementation: `claude-code`"); the *pluggable* claim of ADR-003 stands. Symmetric to ADR-008 for verifiers.

## Context

ADR-003 set up a pluggable backend interface as an OCaml module signature, then narrowed v0 to ship one concrete adapter (`Backend_claude`) baked into `lib/`. The v0 implementation accumulated Claude-Code-specific knowledge inside k4k:

- `lib/backend_claude.ml` — subprocess invocation, `--output-format json` parsing, retry policy
- `kb/external/claude-code.md` — runtime-behavior documentation framed as a *k4k* concern
- prompt-design constraints scoped to "what works on Claude" before generalizing

The same architectural argument that motivated ADR-008 (verifier-agnostic) applies here. The user explicitly accepted that argument when ADR-008 landed; not extending it to backends would leave a known leak in `lib/`.

ADR-003 also captured a forward commitment: prompts must work on the *weakest supported backend* (target Ollama 7B-class) so that switching backends is a configuration change, not a re-engineering project. That commitment was meaningful when there was a privileged in-tree adapter to switch *from*. After ADR-009 it becomes the natural state of affairs: every backend is a configurable plug, none privileged.

## Decision

1. **k4k ships only one backend adapter: `lib/Backend_external`** — a generic process-spawner that invokes a configured executable per the protocol in `kb/external/backend-protocol.md` and parses a JSON result. Plus `lib/Backend_stub` for tests (kept; the Strong/Weak profile is still useful for testing prompt robustness).
2. **`lib/Backend_claude` is removed.** Its behavior — subprocess invocation of `claude -p`, JSON wrapper parsing, retry policy — moves to a standalone executable shipped at `examples/backends/claude-code/`. That executable is a worked example, not a privileged piece of k4k.
3. **The backend is configured in the interaction file's frontmatter** (`k4k.backend.command`, `k4k.backend.timeout_s`). No default `command` — declaring it is part of stability per `EUNSTABLE`.
4. **The OCaml-internal `Agent_backend.S` signature is retained** for type-level wiring inside k4k, but no longer treated as the public extension surface — that role moves to the wire protocol.
5. **Adding a new backend (Ollama, OpenAI, OpenRouter, anything) requires zero changes to k4k's source.** It is a new external executable conforming to the protocol, plus documentation co-located with that executable.
6. **`kb/external/claude-code.md` is removed** (its content moves to `examples/backends/claude-code/README.md`). `kb/external/ollama.md` is retained as architectural guidance for prompt design under the weakness profile, since `conventions/context-economy.md` still references those constraints.

## Consequences

**Wins:**
- k4k's `lib/` is backend-agnostic by construction. The module inventory loses one (`Backend_claude`, 163 lines) and gains one (`Backend_external`, expected ≤ 200 lines).
- The KB's `external/` directory loses a tool-specific document (`claude-code.md`); the protocol doc replaces it. Future backends do not bloat the KB.
- The user's interaction file is now self-describing about *which* backend it expects — same property the verifier retrofit gave us.
- The "weakest supported backend" commitment from ADR-003 becomes naturally enforceable: every backend is plug-in, so the test suite can exercise any of them via `Backend_external` configured against a test stub or against a real Ollama instance.
- `prompts/{formalize,gap-step,kb-regen}.md` remain in k4k (they're produced by k4k's prompt composition step from the formal characterization) — but their *delivery* to whatever LLM is now the backend executable's job.

**Costs:**
- Refactor cost: existing tests that referenced `Backend_claude` need to be updated or moved. The integration tests (S1, NF1) currently use `Backend_stub` with `K4K_STUB_RESPONSES` for canned-response delivery — that path is retained and preferred for offline CI. Live-mode tests gated by `K4K_LIVE=1` will go through the new reference executable instead.
- The example binary still lives in this repo (`examples/backends/claude-code/`). It is built by the same `dune-project` for convenience but is not part of the k4k installable surface.
- `k4k.backend:` becomes a required frontmatter field. Existing `.k4k` fixtures need updating (only one — `tests/fixtures/echo-upper.k4k`).

**v1 Ollama path:**
- `examples/backends/ollama/` is the obvious follow-up — a small executable that takes the protocol's input and posts to `http://localhost:11434/api/generate`. No k4k change needed. ADR-003's "Ollama-readiness" commitment is now satisfied by the protocol's existence; the missing piece is just the example binary.

## What this means for implementers

- **Never reach for `external/<tool>.md` from k4k's source.** If you find yourself wanting to know "how does Claude Code format its output", you are in the wrong file — that knowledge lives in the example's README.
- **The `Backend_external` adapter is the only `lib/backend_*.ml` that may exist** (alongside `Backend_stub` for tests).
- **Tests that need a real backend** invoke `examples/backends/claude-code/main.exe` (built by dune as part of the same project) via the protocol. They do not import any module specific to Claude.
- **Prompt composition stays in k4k.** The `prompts/*.md` templates and the substitution logic in `lib/prompts.ml` remain — the backend just receives the rendered prompt text. Context-economy rules from `conventions/context-economy.md` still apply at the prompt-template level.
- **Two-run formalization invariance.** The reference backend MUST NOT cache identical prompts; this would defeat ADR-005. Document the requirement; verify against the reference implementation.

## Migration story for v0+ users

Anyone running k4k pre-ADR-009 with the bundled `Backend_claude` must:
1. Update their `<file.k4k>` frontmatter to declare `k4k.backend.command` pointing at the example binary.
2. Continue setting `ANTHROPIC_API_KEY` (the example binary inherits the env, like `Backend_claude` did).

The example binary's path is documented in `examples/backends/claude-code/README.md`.

## Relationship to ADR-003

ADR-003 said:
> Agent backends are pluggable via an OCaml module signature; v0 ships claude-code, but every prompt is designed against the weakest supported backend.

ADR-009 keeps the *pluggability claim* and the *weakness-profile prompt design* and changes the *plug shape* from "OCaml module signature, one adapter per tool" to "wire protocol over JSON files, one generic adapter". The `Agent_backend.S` signature still exists in `lib/`; it just has only one production-grade implementation (`Backend_external`) and a test stub.
