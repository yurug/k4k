---
id: external.claude-code
type: external
summary: Runtime behavior of `claude -p` (headless mode) as the v0 agent backend — invocation surface, output format, request budget, failure modes.
domain: external
last-updated: 2026-05-02
depends-on: [glossary, spec.api-contracts]
refines: []
related: [adr-003, conventions.context-economy]
---

# External: Claude Code (headless)

## One-liner

v0's only live agent backend. Invoked as a subprocess (`claude -p <prompt>`) in headless mode. Authentication is inherited from the user's environment; k4k never reads or writes credentials.

## Scope

Actual runtime behavior as observed by k4k. Not a re-statement of the public docs; this file flags operational subtleties an implementer needs to know *before* writing code.

## Invocation surface (what k4k calls)

```
claude -p <prompt>
       --output-format <text|json|stream-json>
       --max-turns <N>                          # cap internal agent turns
       --permission-mode <readOnly|acceptEdits|...>
       --no-color
       --add-dir <path>                         # restrict working directory
       --append-system-prompt <text>            # inject k4k's harness instructions
```

For v0, k4k always uses:
- `--output-format json` (parseable wrapper around the model output)
- `--max-turns 1` for formalization (one shot, no iterative tool use)
- `--max-turns N` (configurable) for gap-step prompts (allows the agent to read/edit during the patch generation)
- `--permission-mode readOnly` for formalization; `acceptEdits` for gap-step (subject to a sandboxed working-tree branch)
- `--append-system-prompt` carrying k4k-specific constraints (output schema, no-prose rule, …)

## Authentication

- k4k does not read `ANTHROPIC_API_KEY` or any credential file.
- The subprocess inherits the parent environment in full.
- Failure mode: `claude` exits non-zero with a "not authenticated" message → k4k surfaces `EAGENT_UNAVAILABLE`.

## Process model

- One subprocess per `Agent_backend.invoke` call. No daemon, no persistent connection.
- Startup cost: ~1-3 seconds (binary load + auth check). Counts toward `duration_ms` but not toward budget.
- The parent (k4k) reads stdout/stderr to completion before returning from `invoke`; no streaming consumption in v0.

## Output shape (`--output-format json`)

The wrapper looks roughly:
```json
{
  "session_id": "...",
  "transcript": [...],
  "result": { "type": "text", "text": "...", "stop_reason": "end_turn" },
  "usage": { "input_tokens": 1234, "output_tokens": 567, ... }
}
```

k4k consumes:
- `result.text` → the response text (parsed downstream by `Stability` / `Gap_step` per their schemas).
- `usage.input_tokens + usage.output_tokens` → `budget_used` (mapped 1:1 to budget units in v0).
- `result.stop_reason` → if not `end_turn`, log a warning.

## Request budget

| Operation               | Typical input tokens | Typical output tokens | Notes                                  |
|-------------------------|----------------------|------------------------|----------------------------------------|
| Formalization (one run) | 2k–4k                | 1k–3k (JSON AST)       | Prompt-design constraint; see ADR-003 |
| Gap-step prompt         | 3k–6k                | 1k–4k (diff)           | Includes scratch context               |
| KB-regen (per file)     | 1k–2k                | 0.5k–1.5k              | Smaller, file-scoped                   |

Per `properties/non-functional.md#NF8`, prompts MUST stay within these envelopes so they remain portable to a 7B-class local backend. Headroom on Claude is intentional unused capacity.

## Failure modes

| Failure                                  | Detection                                | k4k action                                                |
|------------------------------------------|------------------------------------------|-----------------------------------------------------------|
| Binary missing on `$PATH`                | `execvp` ENOENT                          | `EAGENT_UNAVAILABLE`, exit 3                              |
| Authentication failure                   | Non-zero exit + auth-error in stderr     | `EAGENT_UNAVAILABLE`, exit 3                              |
| Network timeout                          | Non-zero exit + transient-error in stderr| Retry up to 3× with exponential backoff; then `EAGENT_UNAVAILABLE` |
| Context window exceeded                  | `result.stop_reason == "context_overflow"` (or non-zero exit) | Treat as a malformed response; mark unstable / patch rejected |
| Rate limit                               | Non-zero exit + 429 hint in stderr       | Honor `Retry-After` if surfaced; otherwise back off + retry  |
| Model produces non-JSON when JSON asked  | JSON parse failure on `result.text`      | Retry once with stricter prompt; then mark patch rejected     |

All retries count toward the per-call and per-invocation budget caps.

## Sandboxing and side effects

In v0, gap-step calls allow `claude` to edit the working tree (necessary to author OCaml source). Mitigations:
- The harness creates a *scratch git branch* before each gap-step (`P5` / `Gap_step.git_create_scratch_branch`); rollback via `git reset --hard`.
- `--add-dir` restricts the working directory the agent can see.
- Anything the agent writes outside the scratch branch tree (e.g. `~/.claude/`) is the user's responsibility to audit.

## Determinism caveat

The agent is **not deterministic**. The harness's determinism contract holds at the canonical-AST layer (ADR-005). Consequences for this backend:
- Two independent `invoke`s on the same prompt may yield different `result.text`.
- Two different patches may be proposed for the same property; both may pass the verifier.
- Test names may be paraphrased; the `P<id>_<slug>` convention is enforced by k4k's prompt template, not by the model alone — verify on parse.

## Cost model

Tokens are billed externally. k4k caps spend via:
- `Agent_backend.invoke ~budget`: hard pre-call check (refuse if `used + budget > hard_per_invocation`).
- Soft per-step cap: refuse to issue any single call larger than `soft_per_step`.

`usage.input_tokens + usage.output_tokens` is the authoritative `budget_used`. v0 does not estimate; it reads the wrapper.

## Versioning

- k4k records `claude --version` output in `manifest.agent_backend.version` on every run.
- A version change since the last `last_stable_at` timestamp does *not* invalidate `D` (the canonical AST is the contract); it does prompt a JSONL warning.

## Agent notes

> **Subprocess only, no SDK in v0.** ADR-003 keeps dependencies minimal; SDK adoption deferred to v1+. If you find yourself reaching for `@anthropic-ai/sdk` from OCaml, stop — wire stdin/stdout instead.
>
> **Beware the lazy-load.** `claude` initializes its tool registry, MCP servers, plugins, etc. on every subprocess. Startup is non-trivial; budget for it and avoid micro-batching calls.

## Related files

- `spec/api-contracts.md#agent-backend` — the signature this implementation satisfies
- `architecture/decisions/adr-003-pluggable-backend.md` — why subprocess and why one backend
- `conventions/context-economy.md` — prompt-design rules referenced above
