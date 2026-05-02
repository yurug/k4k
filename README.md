# k4k — KISS for KISS

A deterministic harness that drives a coding agent to build POSIX-like CLI programs from a user-edited spec, accepting only patches a verifier validates.

## Status

**v0 + ADR-008 retrofit** — runs end-to-end on a toy program. 179 tests green; Phase-5 audit passes 0 criticals across all 7 axes. The ADR-008 retrofit removed verifier-specific code from `lib/`: k4k now ships only `Verifier_external`, a generic adapter that delegates to any executable conforming to `kb/external/verifier-protocol.md`. Adding Rocq, Frama-C, Verus, AFL, etc. requires zero k4k changes — write an executable, set `k4k.verifier.command` in your `<file.k4k>`. Still on the v1+ list: Ollama backend, additional program classes beyond `cli`.

## What it does, in one paragraph

You write a Markdown spec (`myproject.k4k`) describing the CLI you want — goal, inputs/outputs, error taxonomy, acceptance examples, refusing examples. You run `k4k myproject.k4k` in an empty git repo. k4k:

1. **Checks the spec is stable** — has every required section *and* the formal characterization (extracted by an agent, two independent runs) is unambiguous.
2. **Computes the gap** between what the spec demands and what the source code (currently empty) provides.
3. **Drives the agent**, gap-step by gap-step, picking the highest-risk property each time. Each proposed patch lands on a scratch git branch; the verifier (a user-configured executable — the bundled reference verifier runs `dune build @runtest` for OCaml projects) decides whether it satisfies the property — *not* the agent.
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

flags:  -v / --vv                 verbosity (stderr text + JSONL events)
        --max-steps N
        --budget M
        --verifier "<cmd>"        override the verifier command for this run
        --verifier-timeout N      override the verifier wall-clock cap (seconds)
```

`--status`, `--reset`, and `--no-color` are listed in `kb/domain/prd.md` but not yet implemented — see the *Limitations of v0* section.

The interaction file is the primary configuration source — `k4k.verifier.command` (a list of strings) and `k4k.verifier.timeout_s` are required/optional fields under the YAML frontmatter. CLI flags above are short-lived overrides.

Exit codes: `0` done · `1` unstable spec / user error · `2` verifier error · `3` agent backend error · `4` budget / max-steps / disk full · `5` corrupt state.

## Plugging in your own verifier

Per ADR-008, k4k carries no verifier-specific code. To verify with anything other than the bundled OCaml/dune reference, write an executable that:

- Accepts `--workdir <path> --focus <id>... --output <path>`.
- Reads source under `<workdir>`.
- Writes a JSON result file to `<output>` matching the schema in `kb/external/verifier-protocol.md` (per-property status: `established | contradicted | unknown`, plus exit code, duration, optional warnings).
- Exits 0 on result-written, 1 (or any non-zero) on tool failure.

Then set `k4k.verifier.command: ["./your-verifier"]` in your `<file.k4k>` frontmatter. No code in `lib/` changes; no need to recompile k4k. See `examples/verifiers/dune-ocaml/main.ml` (215 lines) as a worked example.

## Running with a real agent

```bash
# Set up Claude Code authentication (one-time)
claude  # follow prompts

# Then drive k4k against the live agent:
K4K_LIVE=1 k4k myproject.k4k
```

`Backend_claude` invokes `claude -p <prompt> --output-format json --max-turns 1 --permission-mode readOnly` for formalization and `acceptEdits` (within a scratch branch) for gap-steps. v0 ships *only* this backend. Architecture is Ollama-ready (see `kb/architecture/decisions/adr-003-pluggable-backend.md`); v1 ships the implementation.

## What lives where

```
bin/main.ml            CLI entry, argv parsing (cmdliner), DI wiring
lib/                   30 modules, each ≤ 200 lines, each function ≤ 30 lines
prompts/               formalize.md, gap-step.md, kb-regen.md (kb-regen is wired but inactive in v0 — see ADR-007)
test/{unit,integration,edge}/  173 tests; weakness profile is the default
tests/fixtures/        echo-upper.k4k + canned-responses.json
kb/                    the meta knowledge base — describes k4k itself
```

The **target KB** k4k generates for the program it builds lives in `.k4k/` of that target project (per ADR-006). It documents that program, not k4k.

## The methodology

This project was built using **spec-driven agentic development**: ambiguity resolution → knowledge base → plan → Ralph-Loop implementation → multi-axis audit → KB sync → docs. The methodology lives in [`agentic-dev-kit/`](agentic-dev-kit/) (sibling submodule). The KB at [`kb/`](kb/) is the source of truth — every code change starts from a KB file.

Phase tracker (and what each phase produced) lives at [`kb/INDEX.md`](kb/INDEX.md).

## Why "KISS for KISS"?

The harness is itself kept stupidly simple so it can build computer programs that are kept stupidly simple. We exclude complex GUIs, large webapps, and big software stacks. We target POSIX-like CLIs and libraries with well-specified I/O whose behavior is fully determined by argv + filesystem contents. See [`kb/NOTES.md`](kb/NOTES.md) for the founding vision.

## Limitations of v0 (explicit, not lurking)

- One agent backend (Claude Code via subprocess). Ollama is architected for, not shipped.
- One *reference* verifier (`examples/verifiers/dune-ocaml/` — runs `dune build @runtest` over OCaml). Rocq / Frama-C / Verus / AFL all need *zero k4k changes* — write an executable matching `kb/external/verifier-protocol.md` and point `k4k.verifier.command` at it.
- One program class (`cli`). `library`, `filter`, others are v1+.
- No GUI, no TUI dashboards beyond the in-place TTY status line.
- No sandboxing of agent-written code — runs in your working tree with your privileges. Run in a container or VM if that matters to you.
- v0's target-KB regenerator is deterministic in-process; it produces structured-but-formulaic prose. Switch to agent-driven for v1+ (one config flag, see ADR-007).
- `--status`, `--reset`, and `--no-color` are spec-claimed in `kb/domain/prd.md` but not wired in `bin/main.ml`. The Phase-5 Axis-5 audit dry-pass missed this; v1 either implements them or demotes the PRD claim.

## License

MIT (project itself). Note the sibling `agentic-dev-kit/` and `others/` directories carry their own provenance — read them before redistributing.
