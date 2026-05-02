---
id: architecture.overview
type: concept
summary: Module structure, DI pattern, dependency graph, error hierarchy. The wiring diagram from `main` down to backend/verifier.
domain: architecture
last-updated: 2026-05-02
depends-on: [glossary, spec.api-contracts, spec.algorithms]
refines: []
related: [architecture.decisions, conventions.code-style, conventions.error-handling]
---

# Architecture Overview

## One-liner

k4k is a small OCaml CLI organized as a deterministic harness wrapping two pluggable interfaces (agent backend, verifier). All I/O passes through dependency-injected modules so the test suite runs against in-memory stubs.

## Scope

How the modules in `bin/` and `lib/` are wired. *Why* the choices are this way lives in `decisions/`. *What* each module does (procedures, types) lives in `spec/`.

## Top-level module graph

```
                          ┌─────────────────────────────┐
                          │  bin/main.ml (entry point)  │
                          └─────────────┬───────────────┘
                                        │  parses argv,
                                        │  composes Harness
                                        ▼
   ┌─────────────────────────────────────────────────────────────────────┐
   │                        lib/Harness                                  │
   │   - top-level loop                                                  │
   │   - ownership-flip detection                                        │
   │   - budget bookkeeping                                              │
   └────┬───────────┬──────────────┬─────────────────┬──────────┬───────┘
        │           │              │                 │          │
        ▼           ▼              ▼                 ▼          ▼
  ┌─────────┐  ┌─────────┐   ┌──────────────┐  ┌──────────┐  ┌────────┐
  │ Parser  │  │ Stable  │   │  Gap_step    │  │  Kb_regen│  │ Logger │
  │         │  │ ility   │   │              │  │          │  │        │
  └─────────┘  └────┬────┘   └──────┬───────┘  └────┬─────┘  └────────┘
                    │               │               │
                    ▼               ▼               ▼
             ┌──────────────────────────────┐ ┌─────────────┐
             │ Agent_backend (signature)    │ │  Verifier   │
             │   impls:                     │ │  (signature)│
             │     Backend_claude           │ │   impls:    │
             │     Backend_stub             │ │     Verifier_dune_ocaml │
             │     (future: Backend_ollama) │ │     Verifier_stub       │
             └──────────────────────────────┘ └─────────────┘
                    │                                │
                    │  subprocess / HTTP             │  subprocess (`dune build`/`dune runtest`)
                    ▼                                ▼
              external service                  local toolchain
```

`Persist` (file I/O for `.k4k/`, atomic writes, locking) is a peer of the above; every module that writes goes through it. `Canonicalize` is a pure library used by both `Stability` and `Gap_step`.

## Modules

### `lib/Parser`
Pure. Reads a `<file.k4k>` byte-string, returns `interaction_file` or `parse_error`. No I/O beyond the read. Section ownership tags + frontmatter only; *not* the formalization step.

### `lib/Stability`
Two stages — structural validation against the parsed sections, then the formalization pass via `Agent_backend`. Returns `Stable | Unstable of issue list`. On unstable, composes the clarification block (text only; the actual write is `Persist`'s job).

### `lib/Canonicalize`
Pure. Takes a raw `Characterization` AST, returns the canonical form + content hash. Single source of truth for the determinism boundary (`P4`, ADR-005).

### `lib/Gap_step`
One iteration of the harness loop. Selects the next property by `risk_score`, composes a prompt, calls `Agent_backend.invoke`, applies the diff on a scratch git branch, calls `Verifier.run`, accepts or rejects.

### `lib/Kb_regen`
Computes the diff between previous and current `(D, S)`; for each affected aspect, identifies the KB files (via `manifest.kb_source_map`) whose ownership is `k4k`, and regenerates them via one agent call per file.

### `lib/Persist`
All file I/O. Atomic writes via tmp+fsync+rename. `flock(2)` discipline. Holds the only handle to `.k4k/`.

### `lib/Logger`
Both human-readable stderr and JSONL `.k4k/log.jsonl`. The TTY status updater is a separate sub-module (`Logger.Tty_status`) that draws the in-place line.

### `lib/Harness`
The top-level loop. Holds the dependency-injected `Agent_backend` and `Verifier` impls; calls the above in order; enforces the budget cap and `--max-steps`.

## Dependency injection

The harness is constructed once in `bin/main.ml`:

```ocaml
let () =
  let agent : (module Agent_backend) =
    match Cli.backend_choice with
    | `Claude_code  -> (module Backend_claude)
    | `Stub         -> (module Backend_stub)
  in
  let verifier : (module Verifier) =
    match Cli.verifier_choice with
    | `Dune_ocaml -> (module Verifier_dune_ocaml)
    | `Stub       -> (module Verifier_stub)
  in
  let module H = Harness.Make ((val agent)) ((val verifier)) in
  H.run Cli.file
```

No global state. No environment lookups outside `bin/main.ml` and the backend modules themselves.

## Error hierarchy (OCaml)

```ocaml
type error =
  | E_format   of { line : int; col : int; reason : string }
  | E_unstable of issue list
  | E_version  of { found : int; supported : int list }
  | E_class_unsupported of string
  | E_budget   of { used : int; cap : int }
  | E_max_steps of int
  | E_agent_unavailable of string
  | E_verifier_unavailable of string
  | E_verifier_tool_error of string
  | E_disk_full of string
  | E_state_corrupt of string
  | E_encoding of int               (* byte offset *)
  | E_file_not_found of string
  | E_file_too_large of int

exception K4k_error of error        (* exit code via Error_taxonomy.exit_code_of *)
exception Invariant_violation of string  (* panics, exit 64+ *)
```

Every public function that may fail documents which constructors it can produce. No naked `Failure _` outside library boundaries. See `conventions/error-handling.md`.

## File layout (planned source tree)

```
k4k/
  bin/
    main.ml                # CLI entry, argv parsing, DI wiring
    main.mli
  lib/
    parser.ml{,i}
    stability.ml{,i}
    canonicalize.ml{,i}
    gap_step.ml{,i}
    kb_regen.ml{,i}
    persist.ml{,i}
    logger.ml{,i}
    harness.ml{,i}
    error.ml{,i}
    backend_claude.ml{,i}
    backend_stub.ml{,i}
    verifier_dune_ocaml.ml{,i}
    verifier_stub.ml{,i}
  prompts/
    formalize.md
    gap-step.md
    kb-regen.md
  test/
    unit/<one-per-lib-module>.ml
    integration/<scenario>.ml
    property/<invariant>.ml
  dune-project
  k4k.opam
```

Source-tree organization matches module names, no surprises.

## Invariants enforced architecturally

- **No I/O outside `Persist`** (except: the agent and verifier modules, whose I/O is to external processes; and `Logger`, which writes stderr and JSONL).
- **No global state.** Module signatures expose `type t`; everything is constructed in `main.ml`.
- **No raise outside `Error.K4k_error`** in user-visible paths; internal panics go through `Error.Invariant_violation` and exit 64+.
- **Files < 200 lines, functions < 30 lines.** Hard limit; lint-checked.

## Agent notes

> **One DI surface.** Adding a backend or verifier should not touch `Harness`, `Stability`, or `Gap_step`. If your change does, the seam is misdrawn — see ADR-003/004 and reconsider.
>
> **Pure where possible.** `Canonicalize`, `Parser`, `Kb_regen.diff` are pure. The test suite leans heavily on this; please don't sneak `Sys.getenv` into them.

## Related files

- `decisions/adr-001-ocaml-dune.md`
- `decisions/adr-002-interaction-file-format.md`
- `decisions/adr-003-pluggable-backend.md`
- `decisions/adr-004-verifier-extension.md`
- `decisions/adr-005-canonical-ast.md`
- `decisions/adr-006-two-layer-kb.md`
- `conventions/code-style.md`
- `conventions/error-handling.md`
