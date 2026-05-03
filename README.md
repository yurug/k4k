# k4k — KISS for KISS

A deterministic harness that drives a coding agent to build POSIX-like CLI programs from a user-edited spec, accepting only patches a verifier validates.

## Status

**v0 + ADR-008 + ADR-009 retrofits + post-audit gap closure** — runs end-to-end on a toy program. **199 tests green** (179 unit + 16 integration + 4 edge); Phase-5 audit passes 0 criticals across all 7 axes after the skeptical second pass closed 2 criticals + 7 highs the dry-pass missed.

The ADR-008 (verifier) and ADR-009 (backend) retrofits stripped tool-specific code out of `lib/` entirely. k4k now ships:

- `lib/Verifier_external` — generic verifier adapter (delegates to any executable conforming to `kb/external/verifier-protocol.md`)
- `lib/Backend_external` — generic agent-backend adapter (delegates to any executable conforming to `kb/external/backend-protocol.md`)

…and three reference examples that are NOT linked into k4k:

- `examples/verifiers/dune-ocaml/` — OCaml + dune verifier (runs `dune build @runtest`)
- `examples/backends/claude-code/` — Anthropic Claude Code backend (subprocess `claude -p`)
- `examples/backends/ollama/` — local Ollama backend (curl to `/api/generate`); live-verified against `qwen3.5:9b`

Adding Rocq, Frama-C, Verus, AFL, OpenAI, OpenRouter, etc. requires **zero k4k changes** — write an executable matching the relevant protocol, declare it in `<file.k4k>` frontmatter. Still on the v1+ list: additional program classes beyond `cli`.

## What it does, in one paragraph

You write a Markdown spec (`myproject.k4k`) describing the CLI you want — goal, inputs/outputs, error taxonomy, acceptance examples, refusing examples. You run `k4k myproject.k4k` in an empty git repo. k4k:

1. **Checks the spec is stable** — has every required section *and* the formal characterization (extracted by an agent, two independent runs) is unambiguous.
2. **Computes the gap** between what the spec demands and what the source code (currently empty) provides.
3. **Drives the agent**, gap-step by gap-step, picking the highest-risk property each time. Each proposed patch lands on a scratch git branch; the verifier (a user-configured executable — the bundled reference runs `dune build @runtest` for OCaml projects) decides whether it satisfies the property — *not* the agent. The agent itself is also a user-configured executable (Claude Code, local Ollama, or anything else satisfying the backend protocol).
4. **Converges** to a working program. Along the way it writes a target KB inside `.k4k/` (your program's documentation, kept in sync with reality).

The harness is **deterministic on the canonical AST** even though the agent is stochastic. It never trusts agent self-assessment for validity — only the verifier and you decide.

## Quick start

```bash
# 1. Install the OCaml toolchain (if needed)
opam install . --deps-only --with-test

# 2. Build
dune build

# 3. Run the test suite (offline, no API calls)
dune runtest

# 4. Try it on the bundled echo --upper example
cd /tmp && rm -rf demo && mkdir demo && cd demo && git init -q
cp ~/path/to/k4k/tests/fixtures/echo-upper.k4k .
cp ~/path/to/k4k/tests/fixtures/echo-upper-canned.json .
git add -A && git commit -q -m initial
K4K_STUB_RESPONSES=$PWD/echo-upper-canned.json k4k echo-upper.k4k
# → done. .k4k/ contains the target KB; the working tree contains a buildable echo CLI.
```

## Command surface

```
k4k <file.k4k>             full convergence loop (default --max-steps 50, --budget 1000)
k4k --check <file.k4k>     stability-only path; no gap-step calls

k4k --status <file.k4k>        print the current gap (one property per line)
k4k --reset <file.k4k> --yes   wipe .k4k/ for this project (--yes required)

flags:  -v / -vv                  verbosity (stderr text + JSONL events; -vv adds subprocess argv)
        --no-color                disable ANSI escapes globally
        --max-steps N
        --budget M
        --verifier "<cmd>"        override the verifier command for this run
        --verifier-timeout N      override the verifier wall-clock cap (seconds)
        --backend "<cmd>"         override the backend command for this run
        --backend-timeout N       override the backend wall-clock cap (seconds)
```

The interaction file is the primary configuration source — `k4k.backend.command` and `k4k.verifier.command` (lists of strings) are required fields under the YAML frontmatter; `*_timeout_s` fields are optional. CLI flags above are short-lived overrides.

Exit codes: `0` done · `1` unstable spec / user error · `2` verifier error · `3` agent backend error · `4` budget / max-steps / disk full · `5` corrupt state.

## Plugging in your own verifier

Per ADR-008, k4k carries no verifier-specific code. To verify with anything other than the bundled OCaml/dune reference, write an executable that:

- Accepts `--workdir <path> --focus <id>... --output <path>`.
- Reads source under `<workdir>`.
- Writes a JSON result file to `<output>` matching the schema in `kb/external/verifier-protocol.md` (per-property status: `established | contradicted | unknown`, plus exit code, duration, optional warnings).
- Exits 0 on result-written, 1 (or any non-zero) on tool failure.

Then set `k4k.verifier.command: ["./your-verifier"]` in your `<file.k4k>` frontmatter. No code in `lib/` changes; no need to recompile k4k. See `examples/verifiers/dune-ocaml/main.ml` (215 lines) as a worked example.

## Plugging in your own backend

Per ADR-009, k4k carries no backend-specific code (symmetric to ADR-008 for verifiers). To drive k4k with anything other than the bundled examples, write an executable that:

- Accepts `--purpose <formalization|gap-step|kb-regen> --prompt-file <path> --budget <int> --output <path>`.
- Reads the prompt from the file.
- Calls whatever LLM (Anthropic, OpenAI, OpenRouter, local Ollama, …).
- Writes a JSON result to `<output>` matching `kb/external/backend-protocol.md` (`outcome ∈ {ok, budget_exhausted, tool_error}`, `text`, `budget_used`, `duration_ms`).
- Exits 0 on result-written, 1 (or any non-zero) on tool failure.

Set `k4k.backend.command: ["./your-backend"]` in your `<file.k4k>` frontmatter. See `examples/backends/claude-code/main.ml` (~190 lines) and `examples/backends/ollama/main.ml` (~210 lines) as worked examples.

## Running with a real agent

```bash
# Option A: Claude Code (Anthropic)
claude  # one-time auth setup
# In your <file.k4k> frontmatter:
#   k4k.backend.command: ["/path/to/k4k/_build/default/examples/backends/claude-code/main.exe"]

# Option B: local Ollama
ollama pull qwen3.5:9b   # 9B-class, ~6 GB
# In your <file.k4k> frontmatter:
#   k4k.backend.command: ["/path/to/k4k/_build/default/examples/backends/ollama/main.exe", "--model", "qwen3.5:9b"]
```

## What lives where

```
bin/main.ml            CLI entry, argv parsing (cmdliner), DI wiring
lib/                   the harness — agnostic to any specific backend or verifier;
                       each file ≤ 200 lines, each function ≤ 30 lines
examples/backends/     reference backend executables (claude-code, ollama)
examples/verifiers/    reference verifier executables (dune-ocaml)
prompts/               formalize.md, gap-step.md, kb-regen.md
test/{unit,integration,edge}/   199 tests; weakness profile is the default
tests/fixtures/        echo-upper.k4k + canned-responses.json
kb/                    the meta knowledge base — describes k4k itself
```

The **target KB** k4k generates for the program it builds lives in `.k4k/` of that target project (per ADR-006). It documents that program, not k4k.

## The methodology

This project was built using **spec-driven agentic development**: ambiguity resolution → knowledge base → plan → Ralph-Loop implementation → multi-axis audit → KB sync → docs. The methodology lives in [`agentic-dev-kit/`](agentic-dev-kit/) (sibling submodule). The KB at [`kb/`](kb/) is the source of truth — every code change starts from a KB file.

Phase tracker (and what each phase produced) lives at [`kb/INDEX.md`](kb/INDEX.md).

## Why "KISS for KISS"?

The harness is itself kept stupidly simple so it can build computer programs that are kept stupidly simple. We exclude complex GUIs, large webapps, and big software stacks. We target POSIX-like CLIs and libraries with well-specified I/O whose behavior is fully determined by argv + filesystem contents. See [`kb/NOTES.md`](kb/NOTES.md) for the founding vision.

## Limitations (explicit, not lurking)

- Two **reference** examples shipped (`claude-code`, `ollama` for backends; `dune-ocaml` for verifiers). Adding more is a documentation/scripting task; *zero* k4k code changes required.
- One program class (`cli`). `library`, `filter`, others are v1+.
- No GUI, no TUI dashboards beyond the in-place TTY status line.
- No sandboxing of agent-written code — runs in your working tree with your privileges. Run in a container or VM if that matters to you.
- The target-KB regenerator is deterministic in-process; it produces structured-but-formulaic prose. Switch to agent-driven (one config flag, see ADR-007) if you want narrative prose in `.k4k/<files>`.

## License

MIT (project itself). Note the sibling `agentic-dev-kit/` and `others/` directories carry their own provenance — read them before redistributing.
