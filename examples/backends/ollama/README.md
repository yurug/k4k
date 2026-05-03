# Reference backend — Ollama

Standalone executable that bridges k4k's agent-backend wire protocol (`kb/external/backend-protocol.md`) to a local [Ollama](https://ollama.com) server. Worked example, not part of k4k's installable surface.

## What it does

For each call k4k makes:

1. Reads the prompt file k4k wrote.
2. POSTs `{model, prompt, stream:false, options:{num_predict:budget}}` to `<host>/api/generate`.
3. Parses Ollama's response for the model output text and token counts (`prompt_eval_count + eval_count`).
4. Maps to the protocol's outcome:
   - `ok` if the response contained a `response` field and `prompt_eval_count + eval_count ≤ budget`
   - `budget_exhausted` if total tokens exceeded the cap
   - `tool_error` on connection failure, missing model, malformed JSON, or any Ollama-side error
5. Writes the protocol's result JSON atomically.

The `options.num_predict = budget` request field caps model output preemptively. The post-hoc `total_tokens > budget` check is the backstop when the prompt itself overruns the budget.

## How to plug it in

In your `<file.k4k>` frontmatter:

```yaml
---
k4k:
  version: 1
  class: cli
  backend:
    command:
      - "/abs/path/to/ollama_backend"
      - "--model"
      - "qwen3.5:9b"             # or codellama:7b-instruct, mistral, ...
      - "--host"
      - "http://localhost:11434"
    timeout_s: 600                  # local LLMs are slower than hosted APIs
  verifier:
    command: ["./_verifier.exe"]
    timeout_s: 60
---
```

The four protocol flags (`--purpose`, `--prompt-file`, `--budget`, `--output`) are appended by k4k automatically.

## Setup

```bash
# 1. Install Ollama: https://ollama.com/download
# 2. Pull a model
ollama pull qwen3.5:9b      # 9B-class, ~6 GB; closest to k4k's weakness-profile target
# or
ollama pull codellama:7b-instruct

# 3. Confirm the daemon is responding
curl http://localhost:11434/api/tags

# 4. Build k4k's binaries
cd /path/to/k4k && dune build

# 5. Reference the binary in your .k4k:
#    command: ["/path/to/k4k/_build/default/examples/backends/ollama/main.exe", "--model", "qwen3.5:9b"]
```

## Output schema

Per `kb/external/backend-protocol.md`:

```json
{
  "outcome": "ok" | "budget_exhausted" | "tool_error",
  "text":         "<model output>",   // present iff outcome="ok"
  "budget_used":  1234,                // present iff outcome="ok"
  "duration_ms":  5678,                // always present
  "error":        "<reason>"           // present iff outcome="tool_error"
}
```

## Test mode (`--mock-response`)

For offline/CI testing, bypass curl and read a canned Ollama response:

```bash
ollama_backend --mock-response /path/to/canned.json \
  --purpose formalization \
  --prompt-file /path/to/prompt.txt \
  --budget 1000 \
  --output /tmp/result.json
```

The canned file should follow Ollama's `/api/generate` (non-streaming) JSON shape:

```json
{
  "model": "qwen3.5:9b",
  "response": "<the LLM's textual output>",
  "prompt_eval_count": 42,
  "eval_count": 17,
  "done": true
}
```

## Known limitations

- **Local LLMs are weaker than hosted APIs.** Per `kb/conventions/context-economy.md`, k4k's prompt templates target a 7B-class model. Larger Ollama models (e.g. `qwen3.5:27b`, `llama3.1:70b`) work but pay no architectural dividend.
- **No streaming.** k4k's protocol returns one result per call; we set `stream: false`. For interactive UIs this would change.
- **No structured-output enforcement.** Ollama doesn't support OpenAI's `response_format` parameter universally; we rely on k4k's `Permissive_json` to strip code fences and tolerate trailing prose.
- **Two-run formalization compatibility.** Per ADR-005, k4k invokes the backend twice for stability checks; the protocol forbids backend-side caching of identical prompts. Ollama does not cache by default — if you set up a caching reverse proxy, disable it for the formalization purpose.
- **Authentication.** Default is no auth (localhost-only deployment). For TLS-tunneled remote Ollama, set up the tunnel separately; the reference backend does not handle credentials.

## CLI

```
ollama_backend [--model NAME] [--host URL] [--mock-response PATH] \
  --purpose <formalization|gap-step|kb-regen> \
  --prompt-file <abs-path> --budget <int> --output <abs-path>
```

Defaults: `--model codellama:7b-instruct`, `--host http://localhost:11434`. Override either via CLI flags prefixed in `k4k.backend.command`.

## Related

- `kb/external/backend-protocol.md` — the wire contract this implements
- `kb/external/ollama.md` — architectural guidance for prompt design under weak local models
- `kb/architecture/decisions/adr-009-backend-protocol.md` — why this is an external executable, not a `lib/` module
- `examples/backends/claude-code/` — the sibling reference backend (Anthropic Claude Code)
