---
id: external.backend-protocol
type: spec
summary: The wire protocol between k4k and any external agent backend. k4k itself ships zero backend-specific code; users plug in any backend that satisfies this protocol.
domain: external
last-updated: 2026-05-03
depends-on: [glossary, spec.api-contracts, spec.data-model]
refines: [spec.api-contracts]
related: [adr-009, conventions.context-economy]
---

# Backend Protocol

## One-liner

A backend is **any executable** that, given a prompt and a budget cap, returns text plus token usage (or refuses with `budget_exhausted` / `tool_error`). k4k spawns the executable, parses the JSON result, and treats the output as the source of truth — no other coupling.

## Scope

The contract a backend must satisfy. k4k's `lib/Backend_external` is the only adapter required to invoke backends; per-tool code (Anthropic SDK calls, Ollama HTTP requests, OpenAI compatibility shims) lives in the backend executable itself, not in k4k.

A *reference backend* implementing this protocol against `claude` (Claude Code headless) ships at `examples/backends/claude-code/`. It is a worked example, not part of k4k's binary.

## Why a wire protocol (not an OCaml signature)

`Agent_backend.S` (the OCaml signature, retained for type-level wiring inside k4k) is satisfied by **one** concrete adapter (`Backend_external`) that delegates everything beyond JSON parsing to a configured executable. Same architecture as ADR-008 for verifiers; same rationale: k4k carrying tool-specific code violates the KISS thesis from `kb/NOTES.md`.

## Invocation

k4k spawns the backend as:

```
<command> [<extra-args>...] \
  --purpose <formalization|gap-step|kb-regen> \
  --prompt-file <abs-path> \
  --budget <int> \
  --output <abs-path>
```

- `<command>` and any prefix `<extra-args>` come from the interaction file's frontmatter `k4k.backend.command` (a list of strings).
- `--purpose` is one of three string literals indicating which prompt template produced the prompt. The backend MAY use this to vary tool-permission settings (e.g. read-only for formalization, edit-allowed for gap-step) but is not required to.
- `--prompt-file` points to a file containing the rendered prompt text (UTF-8). The harness writes this file atomically before invoking; the backend may read it freely.
- `--budget` is an integer cap on budget units this single call may consume (typically tokens-equivalent). The backend MUST refuse the call with `budget_exhausted` rather than exceeding it.
- `--output` is the destination path for the result JSON. The backend writes atomically (tmp + rename) to avoid the harness reading a partial file.

`stdin` is closed. The backend inherits the harness's environment (so per-backend env vars like `ANTHROPIC_API_KEY` work without forwarding by k4k).

## Result file (`<output>`)

Single JSON object. Schema:

```json
{
  "outcome": "ok" | "budget_exhausted" | "tool_error",
  "text":         "<string>",      // present iff outcome="ok"
  "budget_used":  <int>,           // present iff outcome="ok"; ≤ --budget
  "duration_ms":  <int>,           // always present
  "error":        "<string>"       // present iff outcome="tool_error"
}
```

- `outcome`: one of three string literals. Required.
- `text`: the raw model output. Whatever structure (JSON, diff, prose) it carries is parsed by k4k downstream, not by the backend.
- `budget_used`: tokens-equivalent the call consumed. Must be ≤ `--budget`.
- `duration_ms`: total backend wall-clock in milliseconds. Always present, even on `tool_error`.
- `error`: short human-readable reason for `tool_error`. Surfaced to the user via `EAGENT_UNAVAILABLE` if the harness retries fail.

The result file MUST be valid UTF-8 JSON. k4k uses Yojson to parse; trailing whitespace and a trailing newline are tolerated.

## Backend exit codes (the *process* exit, not anything else)

| Exit | Meaning                                                             | k4k action                          |
|------|---------------------------------------------------------------------|-------------------------------------|
| 0    | Result file written and valid                                       | Continue with the parsed result    |
| 1    | Tool error (e.g. binary missing, transient network, auth failure)   | Retry up to 3× with exponential backoff; then `EAGENT_UNAVAILABLE` |
| 130  | Killed by SIGINT                                                    | `Tool_error "interrupted"`          |
| any other | Same as 1                                                       | Retry then `EAGENT_UNAVAILABLE`     |

If exit is 0 but the result file is missing, unparseable, or has an outcome inconsistent with required fields: `Tool_error`. Retries count toward the per-call budget cap.

## Wall-clock budget

- Per-invocation cap: configured via `k4k.backend.timeout_s` in the interaction file (default 300 s — agent calls are long). On timeout, k4k kills the backend and emits `EAGENT_UNAVAILABLE`.
- The harness's per-call cost accounting reads `budget_used` from the JSON. Budget bookkeeping (`P9`) lives in k4k, not in the backend.

## Non-functional contract

- **Determinism is NOT required.** The backend is the stochastic component of k4k's stack. Determinism is preserved by the canonical-AST contract (ADR-005) and the two-run formalization protocol (`P18`).
- **No interaction.** The backend MUST run non-interactively. No prompts on stdin. No TTY assumptions.
- **No state retention.** The backend MUST treat each invocation as independent. Cross-call state lives in `.k4k/` (specifically `.k4k/agent-runs/<id>/`); the backend MAY consult `.k4k/` for context but MUST NOT mutate it.
- **No side effects on the user's source tree.** Gap-step prompts authorize the agent to propose patches as text; *applying* the patch is the harness's job (via `Git.apply_diff` directly on the in-flight `k4k/version/<n>` branch per ADR-013 §2 step 3). Backends that internally call edit-style tools (e.g. Claude Code's Edit tool) operate on a sandbox the backend itself manages, not on the user's tree.

## Configuration in the interaction file

Required, under `k4k.backend`:

```yaml
---
k4k:
  version: 1
  class: cli
  backend:
    command: ["./scripts/agent.sh"]
    timeout_s: 300
  verifier:
    command: ["./scripts/verify.sh"]
    timeout_s: 60
---
```

The CLI flag `--backend '<command-string>'` overrides `command` for one run; `--backend-timeout N` overrides `timeout_s`. Defaults: `timeout_s = 300`. There is no default for `command` — the interaction file MUST declare one (failing this is `EUNSTABLE`, with a clarification appended).

## Reference backend (worked example)

`examples/backends/claude-code/` ships a reference implementation suitable for users with `claude` (Claude Code) installed. It:
- Reads the prompt file.
- Invokes `claude -p <prompt> --output-format json --max-turns 1 --permission-mode <readOnly|acceptEdits>` (selecting the permission mode based on `--purpose`).
- Parses the JSON wrapper for `result.text`, `usage.input_tokens`, `usage.output_tokens`.
- Refuses with `budget_exhausted` if `input_tokens + output_tokens > --budget`.
- Emits the protocol's result JSON.

To use it, set `k4k.backend.command` to the installed binary's path. See `examples/backends/claude-code/README.md` for the full setup including auth.

## Future / parallel reference backends

- `examples/backends/ollama/` (deferred) — invokes Ollama's HTTP API, applies the weakness profile from `conventions/context-economy.md`. The architectural commitment in ADR-003 is now realized at the *protocol* layer rather than as an OCaml module: any backend can be Ollama-style as long as it conforms.

## Agent notes

> **The protocol is the contract.** Any change to the CLI shape or to the result JSON schema is a breaking change requiring a `k4k.version` bump in the interaction file. Adding optional fields to the result is non-breaking; renaming or removing required fields is breaking.
>
> **k4k carries no backend-specific knowledge.** Switching from Claude to Ollama to OpenAI to whatever-comes-next does not touch k4k's source. It is a new executable conforming to this contract, packaged or distributed separately.
>
> **The two-run formalization protocol still applies.** For `--purpose formalization`, k4k invokes the backend twice with the same prompt. Backends that cache identical-prompt responses internally would defeat ADR-005's ambiguity detection — they MUST NOT cache. (The reference Claude backend does not; check before configuring others.)

## Related files

- `architecture/decisions/adr-009-backend-protocol.md` — the decision record
- `architecture/decisions/adr-003-pluggable-backend.md` — partially superseded by ADR-009 (the *plug shape* moved from OCaml signature to wire protocol; the Ollama-readiness commitment stands at the protocol layer)
- `external/verifier-protocol.md` — symmetric protocol for verifiers (ADR-008)
- `spec/api-contracts.md` — the OCaml-internal `Agent_backend.S` signature `Backend_external` satisfies
- `spec/config-and-formats.md` — the interaction-file schema including `k4k.backend`
- `conventions/context-economy.md` — prompt-design rules (still applicable; k4k composes prompts before passing them to backends)
