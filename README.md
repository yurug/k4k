# k4k — KISS for KISS

A deterministic harness that drives a coding agent to build POSIX-like CLI programs from a user-edited spec, accepting only patches a verifier validates.

## Status

**v0** — runs end-to-end on a toy program. 173 tests green; Phase-5 audit passes 0 criticals across all 7 axes. v1+ adds Ollama backend, more verifiers (Rocq, Frama-C, Verus), and additional program classes.

## What it does, in one paragraph

You write a Markdown spec (`myproject.k4k`) describing the CLI you want — goal, inputs/outputs, error taxonomy, acceptance examples, refusing examples. You run `k4k myproject.k4k` in an empty git repo. k4k:

1. **Checks the spec is stable** — has every required section *and* the formal characterization (extracted by an agent, two independent runs) is unambiguous.
2. **Computes the gap** between what the spec demands and what the source code (currently empty) provides.
3. **Drives the agent**, gap-step by gap-step, picking the highest-risk property each time. Each proposed patch lands on a scratch git branch; the verifier (real `dune build @runtest`) decides whether it satisfies the property — *not* the agent.
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
k4k --status <file.k4k>    print current gap; no work, no agent calls
k4k --reset <file.k4k> --yes   wipe .k4k/ for this project

flags:  -v / -vv     verbosity
        --no-color   disable ANSI in TTY status line
        --max-steps N
        --budget M
```

Exit codes: `0` done · `1` unstable spec / user error · `2` verifier error · `3` agent backend error · `4` budget / max-steps / disk full · `5` corrupt state.

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
- One verifier (`dune build @runtest` over OCaml). Rocq / Frama-C / Verus / AFL all v1+.
- One program class (`cli`). `library`, `filter`, others are v1+.
- No GUI, no TUI dashboards beyond the in-place TTY status line.
- No sandboxing of agent-written code — runs in your working tree with your privileges. Run in a container or VM if that matters to you.
- v0's target-KB regenerator is deterministic in-process; it produces structured-but-formulaic prose. Switch to agent-driven for v1+ (one config flag, see ADR-007).

## License

MIT (project itself). Note the sibling `agentic-dev-kit/` and `others/` directories carry their own provenance — read them before redistributing.
