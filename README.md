# k4k — KISS for KISS

An autonomous coding agent that builds **formally verified** POSIX-like programs from a single user-edited file.

## What it does

You write free-form prose describing the program you want into a `.k4k` file. k4k watches the file, asks clarifying questions in-line until your demand denotes a clear theorem, then develops + verifies the implementation in **full autonomy** — with full formal verification by default (Rocq + extraction to OCaml; Frama-C/ACSL on C; Lean; Verus; F*). Trade-offs to lower verification tiers happen only with your explicit sign-off, in the same file.

You never run flags. You never configure tooling. You never see the verifier or the agent backend. The file is the protocol.

## Status

**v2 — reorientation in progress.**

The v0/v1 build (54 commits, 213 tests, ADR-008/009/010 retrofits, conformance suite, drift-watch) shipped a developer-CLI tool — the wrong product. The v2 reorientation drops the CLI surface, makes k4k a watcher daemon, and switches the default verification tier from testing (`dune-ocaml` Tier C) to formal verification (Rocq-extraction-shaped Tier A). The architectural commitments (cotype delegation, wire-protocol verifier/backend, canonical-AST determinism, two-layer KB, deterministic kb-regen) all survive both UX corrections. The historical record is in [`kb/archive/v0-drifted/`](kb/archive/v0-drifted/).

Phase tracker at [`kb/INDEX.md`](kb/INDEX.md). The current PRD at [`kb/domain/prd.md`](kb/domain/prd.md) is the post-reorientation source of truth.

## Quick start (post-v2; not yet implemented)

```bash
pipx install cotype k4k    # cotype is the file-concurrency primitive (ADR-010)
k4k myproject.k4k          # one-shot launch; thereafter the agent is autonomous
```

After that command, you only edit `myproject.k4k`. k4k:
- Appends `## k4k:clarification:<ts>` blocks until your spec denotes a clear theorem.
- Snapshots a `## k4k:version:<n>` and starts developing in Rocq + extraction to OCaml.
- Updates a `## k4k:status` block live.
- Surfaces `## k4k:tradeoff:proposal:<ts>` if Tier A fails on a property and degradation is warranted; waits for your sign-off in the file.

## Verification tiers

| Tier | What it means | Sign-off |
|---|---|---|
| **A — Full formal verification** | Implementation extracted from / machine-checked against a formal artifact (Rocq+Extraction, Frama-C/ACSL+WP, Lean, Verus, F*…). | Implicit — the goal. |
| **B — Formal model + intensive testing** | A formal model exists; the implementation is hand-written and tested against the model via property-based testing + fuzzing. | Required, in-file, with k4k's written rationale. |
| **C — Testing-only** | No formal artifact. Tests + alcotest. (`examples/verifiers/dune-ocaml/` is a Tier-C example.) | Required, in-file, with explicit acknowledgment that the formal-correctness goal is forfeited for the relevant property. |

Tiers are **per-property**. A program may end up with 10 properties at Tier A and 2 at Tier B; the file's status block reflects the distribution.

## Architecture in one paragraph

`lib/` is the harness — verifier-agnostic, backend-agnostic, concurrency-delegated. Tools enter via wire protocols (`Verifier_external`, `Backend_external` per ADR-008/009) or via a hardcoded runtime dependency (`cotype` per ADR-010, like `git`). The user-facing protocol is the `.k4k` file. The engine inside `lib/` is what was built across v0/v1; the wrapper around it (`bin/main.ml`) is being rebuilt for v2 against the autonomous-watcher UX.

## Repository layout

```
bin/main.ml                  CLI entry — currently the v0 developer-CLI shape; v2 rewrite pending
lib/                         the harness (engine; verifier/backend/concurrency-agnostic)
examples/
  backends/                  reference agent-backend executables (claude-code, ollama)
  verifiers/                 reference verifier executables (dune-ocaml is Tier C)
prompts/                     formalize.md, gap-step.md, kb-regen.md
test/{unit,integration,edge,conformance}/   test suites
kb/                          the meta knowledge base — describes k4k itself
kb/archive/v0-drifted/       historical record of the v0 build under the drifted UX framing
```

## The methodology

This project is built using **spec-driven agentic development** ([`agentic-dev-kit/`](agentic-dev-kit/)). The KB at [`kb/`](kb/) is the source of truth. Two UX corrections from the user (ADR-008/009/010 + the v2 reorientation) reshaped the framing while leaving the architectural primitives intact. Phase tracker at [`kb/INDEX.md`](kb/INDEX.md). Round-1-redux questions for v2 are forthcoming.

## Why "KISS for KISS"

The harness is itself kept stupidly simple so it can build computer programs that are kept stupidly simple. We exclude complex GUIs, large webapps, big software stacks, ML training, GPU/numerics, distributed systems. We target POSIX-like CLIs and libraries with well-specified I/O whose behavior is fully determined by argv + filesystem contents. See [`kb/NOTES.md`](kb/NOTES.md) for the founding vision.

## Not v0 anymore

Anything in this README that looks like a developer-CLI command (flags, status output, etc.) is being rewritten under v2. If you're reading the active KB and find content that contradicts the autonomous-agent + Tier-A framing, file it as drift; the v2 PRD is the resolution authority.

## License

MIT (project itself). Note `agentic-dev-kit/` is a sibling submodule with its own provenance; `kb/archive/v0-drifted/` is the historical record kept verbatim.
