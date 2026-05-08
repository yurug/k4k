# k4k — KISS for KISS

An autonomous coding agent that builds **formally verified** POSIX-like programs from a single user-edited file.

## What it does

You write free-form prose describing the program you want into a `.k4k` file. k4k watches the file, asks clarifying questions in-line until your demand denotes a clear theorem, then develops + verifies the implementation in **full autonomy** — with full formal verification by default (Rocq + extraction to OCaml; Frama-C/ACSL on C; Lean; Verus; F*). Trade-offs to lower verification tiers happen only with your explicit sign-off, in the same file.

You never run flags. You never configure tooling. You never see the verifier or the agent backend. The file is the protocol.

## Quick start

```bash
pipx install cotype                                  # ADR-010 — file-concurrency primitive
dune build && dune install                           # build k4k from this repo

# Build the reference agent backend (or your own conforming binary):
ls _build/install/default/bin/claude_code_backend    # the example, post-build
export K4K_BACKEND_COMMAND="$(pwd)/_build/install/default/bin/claude_code_backend"

# Launch the watcher — once.
k4k myproject.k4k
```

`K4K_BACKEND_COMMAND` points at any executable conforming to
[`kb/external/backend-protocol.md`](kb/external/backend-protocol.md).
Two reference backends ship under `examples/backends/`:
[`claude-code`](examples/backends/claude-code/README.md) (calls
`claude -p`; needs `claude` on `$PATH` + `ANTHROPIC_API_KEY`) and
[`ollama`](examples/backends/ollama/) (calls a local Ollama server).
Without `K4K_BACKEND_COMMAND` set, the watcher logs
`agent.unconfigured` once and idles — useful for `--exit-on-stable`
smokes but not for real work.

To smoke-test the claude-code backend wire (one round-trip; consumes
API tokens):

```bash
./examples/backends/claude-code/smoke.sh formalization
```

After launching the watcher you only edit `myproject.k4k`. k4k:

- Appends `## k4k:clarification:<ts>` blocks until your spec denotes a clear theorem.
- Snapshots a `## k4k:version:<n>` block and develops the version on a `k4k/version/<n>` git branch (per ADR-013). Accepted gap-steps commit as `[k4k] establish <pid>`; on completion k4k merges to `main` and tags `v<n>`.
- Updates a `## k4k:status` block live (per-property statuses, pending user edits, open trade-offs, last activity).
- Surfaces `## k4k:tradeoff:proposal:<ts>` if Tier A fails on a property and degradation is warranted; pauses for your sign-off (`Approved: Tier B` / `Approved: Tier C` / `Rejected: <guidance>`) inline.
- Treats edits you make to your own sections during development as **queued for the next version** — they never interrupt the in-flight gap-step loop. The status block surfaces the count.

## Verification tiers

| Tier | What it means | Sign-off |
|---|---|---|
| **A — Full formal verification** | Implementation extracted from / machine-checked against a formal artifact (Rocq+Extraction, Frama-C/ACSL+WP, Lean, Verus, F*…). | Implicit — the goal. |
| **B — Formal model + intensive testing** | A formal model exists; the implementation is hand-written and tested against the model via property-based testing + fuzzing. | Required, in-file, with k4k's written rationale. |
| **C — Testing-only** | No formal artifact. Tests only. | Required, in-file, with explicit acknowledgment that the formal-correctness goal is forfeited for the relevant property. |

Tiers are **per-property**. A program may end up with 10 properties at Tier A and 2 at Tier B; the file's status block reflects the distribution.

## Architecture in one paragraph

`lib/` is the harness — verifier-agnostic, backend-agnostic, concurrency-delegated. Tools enter via wire protocols (`Verifier_external`, `Backend_external` per ADR-008/009) or via a hardcoded runtime dependency (`cotype` per ADR-010, like `git`). The user-facing protocol is the `.k4k` file. `bin/main.ml` is the watcher daemon; `lib/Watcher_loop` orchestrates stability, formalization, version lifecycle (`lib/Version`, `lib/Version_loop`, `lib/Version_finalize`), the direct-commit gap-step (`lib/Gap_step`), trade-off sign-off (`lib/Tradeoff_flow`, `lib/Version_tradeoff`), and user-edit queueing (`lib/Version_user_edits`).

## Repository layout

```
bin/main.ml                  watcher daemon entry — single CLI form: k4k <file>
lib/                         the harness (engine; verifier/backend/concurrency-agnostic)
examples/
  backends/                  reference agent-backend executables (claude-code, ollama)
prompts/                     formalize.md, gap-step.tier-{a,b,c}.md, kb-regen.md
test/{unit,integration,edge,conformance}/   test suites (~270 tests; see kb/INDEX.md)
kb/                          the meta knowledge base — describes k4k itself
kb/archive/v0-drifted/       historical record of the v0 build under the drifted UX framing
```

## Operator flags

The user UX is in-file; the binary itself takes only `<file>` plus a few operator flags:

- `-v` / `-vv` — verbose / debug stderr (engine-level transitions / subprocess argv).
- `--exit-on-stable` *[test-only]* — exit after the first stability snapshot.
- `--exit-on-done` *[test-only]* — exit once the in-flight version completes or rolls back.

Test-only knobs (env vars) are documented in [`kb/runbooks/test-environment.md`](kb/runbooks/test-environment.md).

## Status

v2 batch 4c is in. The watcher drives a stable spec to a real version-1 completion via real formalization, handles trade-off sign-off + Tier-B/C retry, surfaces user edits queued for the next version, finalizes with audit/merge/tag, and supports rollback via in-file directive. Phase tracker at [`kb/INDEX.md`](kb/INDEX.md). Test count: 268 (243 unit + 15 integration + 6 conformance + 4 edge).

## The methodology

This project is built using **spec-driven agentic development** ([`agentic-dev-kit/`](agentic-dev-kit/)). The KB at [`kb/`](kb/) is the source of truth. Two UX corrections from the user (ADR-008/009/010 + the v2 reorientation in ADR-011/012/013) reshaped the framing while leaving the architectural primitives intact.

## Why "KISS for KISS"

The harness is itself kept stupidly simple so it can build computer programs that are kept stupidly simple. We exclude complex GUIs, large webapps, big software stacks, ML training, GPU/numerics, distributed systems. We target POSIX-like CLIs and libraries with well-specified I/O whose behavior is fully determined by argv + filesystem contents. See [`kb/NOTES.md`](kb/NOTES.md) for the founding vision.

## License

MIT (project itself). Note `agentic-dev-kit/` is a sibling submodule with its own provenance; `kb/archive/v0-drifted/` is the historical record kept verbatim.
