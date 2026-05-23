# Reference agent backend — Claude Code (`claude -p`)

A worked example of an agent backend conforming to k4k's wire protocol
(see `kb/external/backend-protocol.md`). Not part of k4k's installable
surface — it lives here as a reference implementation.

## What it does

For each invocation the binary:

1. Reads the rendered prompt from `--prompt-file`.
2. Passes `--permission-mode acceptEdits` to `claude`. The k4k wire
   protocol's prompts never ask claude to invoke Edit/Write tools
   (formalize returns JSON text, gap-step returns a `<patch>` text
   block), so the permission mode is just a safety policy. (The older
   `readOnly` value was removed from claude's allowed set; `plan` is
   the closest semantic match but it makes claude call `exit_plan_mode`,
   which adds noise under `--max-turns 1`.)
3. Spawns `claude -p <prompt> --output-format json --max-turns 1 --permission-mode acceptEdits`.
4. Parses the JSON wrapper for `result.text` and `usage.input_tokens + usage.output_tokens`.
5. If the token total exceeds `--budget`, emits `outcome: "budget_exhausted"`.
6. On `claude` exit 0 with valid JSON: emits `outcome: "ok"` with the text and
   token usage.
7. On `claude` exit non-zero or JSON parse failure: emits `outcome: "tool_error"`
   with a short message — and still exits 0 (the protocol says exit 0 for any
   well-formed result file).
8. Exits 1 only when the `claude` binary itself is missing on `$PATH`.

## How to plug it in

Add the binary's absolute path to your interaction file's frontmatter:

```yaml
---
k4k:
  version: 1
  class: cli
  backend:
    command: ["/path/to/claude_code_backend"]
    timeout_s: 300
  verifier:
    command: ["/path/to/your-verifier"]
    timeout_s: 60
---
```

The CLI flag `--backend '/path/to/claude_code_backend'` overrides the frontmatter
for one run.

## Output schema

See `kb/external/backend-protocol.md` for the canonical schema. This binary
always writes a single JSON object with the protocol's required fields.

## Auth

The backend inherits the harness's environment, so any auth mechanism `claude`
recognises works — typically `ANTHROPIC_API_KEY` or whatever local
configuration `claude` is set up with. k4k itself does not forward any
credentials; that is the backend's responsibility.

## Testing

Wire-level tests live in `test/integration/test_integration.ml` under
the `claude_code_backend` group: they exercise the binary with
`--mock-response`, validating the protocol output for `ok`,
`budget_exhausted`, malformed-JSON `tool_error`, and the
missing-text-defaults-to-empty edge case. Run them with:

```bash
dune runtest test/integration  # covers everything; ~50s
```

For a real-Claude smoke (consumes API tokens) run `./smoke.sh
formalization` from this directory. The smoke script is opt-in and
not part of the test suite.

## Known limitations

- `--max-turns 1`: a single round-trip per call. If your prompt requires
  multi-turn tool use, raise `--max-turns` in the source and re-build.
- No internal cache: identical prompts produce fresh model calls. This is
  intentional — k4k's two-run formalization protocol (P18) relies on the
  backend NOT caching identical-prompt responses.
- Token accounting uses `usage.input_tokens + usage.output_tokens` from the
  Claude wrapper. If those fields are missing, `budget_used` is 0; the
  budget cap will only fire when the wrapper reports usage explicitly.
- The reference implementation exposes no per-purpose `--max-turns` knob; the
  fixed value of 1 is what the protocol's `--budget` discipline assumes.
