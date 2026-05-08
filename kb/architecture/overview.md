---
id: architecture.overview
type: concept
summary: Module structure, DI pattern, dependency graph, error hierarchy. The wiring diagram from `main` down to backend/verifier.
domain: architecture
last-updated: 2026-05-02
depends-on: [glossary, spec.api-contracts, spec.algorithms]
refines: []
related: [architecture.decisions.index, conventions.code-style, conventions.error-handling]
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
             ┌──────────────────────────────┐ ┌────────────────────────┐
             │ Agent_backend (signature)    │ │ Verifier (signature)   │
             │   impls:                     │ │   impls:               │
             │     Backend_external         │ │     Verifier_external  │
             │     Backend_stub             │ │     Verifier_stub      │
             └──────────────────────────────┘ └────────────────────────┘
                    │                                │
                    │  subprocess invocation of any  │  subprocess invocation of any
                    ▼  user-configured executable    ▼  user-configured executable
            conforming to external/        conforming to external/
            backend-protocol.md            verifier-protocol.md
```

`Persist` (file I/O for `.k4k/`, atomic writes, locking) is a peer of the above; every module that writes goes through it. `Canonicalize` is a pure library used by both `Stability` and `Gap_step`.

## Modules

### `lib/Parser`
Pure. Reads a `<file.k4k>` byte-string, returns `interaction_file` or `parse_error`. No I/O beyond the read. Markdown headings + YAML frontmatter only; *not* the formalization step. Bytes come from `cotype open` → `base_path` per ADR-010, never from the file path directly — the wrapper for that is `lib/cotype.ml`.

### `lib/Stability`
Two stages — structural validation against the parsed sections, then the formalization pass via `Agent_backend`. Returns `Stable | Unstable of issue list`. On unstable, composes the clarification block (text only; the actual write is `Persist`'s job).

### `lib/Canonicalize`
Pure. Takes a raw `Characterization` AST, returns the canonical form + content hash. Single source of truth for the determinism boundary (`P4`, ADR-005).

### `lib/Gap_step`
One iteration of the harness loop (ADR-013 §2 step 3, v2 direct-commit). Composes a tier-aware prompt, calls `Agent_backend.invoke`, applies the diff directly to the working tree (already on `k4k/version/<n>`), runs `Verifier.run` in focus mode, and either commits via `Version.commit_accept` (Accepted) or `git reset --hard HEAD` (Rejected/Tradeoff). Branch management is up to the caller (`Version_loop`); `Gap_step` no longer owns scratch branches.

### `lib/Kb_regen`
Computes the diff between previous and current `(D, S)`; for each affected aspect, identifies the KB files (via `manifest.kb_source_map`) whose ownership is `k4k`, and regenerates them via one agent call per file.

### `lib/Persist`
All file I/O for `.k4k/` operational state. Atomic writes via tmp+fsync+rename. Holds the only handle to `.k4k/`. **The interaction file (`<file.k4k>`) is NOT written by Persist** — that surface goes through `lib/Cotype` (per ADR-010), which delegates to the `cotype` CLI. `lib/Persist_lock` was removed as part of ADR-010 (cotype owns its sidecar lock internally; k4k never calls `flock` from its own code).

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
    | `External -> (module Backend_external)   (* configured via .k4k frontmatter *)
    | `Stub     -> (module Backend_stub)
  in
  let verifier : (module Verifier) =
    match Cli.verifier_choice with
    | `External -> (module Verifier_external)   (* configured via .k4k frontmatter *)
    | `Stub     -> (module Verifier_stub)
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

## File layout (actual source tree, post step 4)

```
k4k/
  bin/main.ml                       # CLI entry, argv parsing, DI wiring
  lib/                              # see module-by-module list below
  examples/
    backends/
      claude-code/                  # reference backend, conforms to wire protocol
        main.ml                     # standalone OCaml binary
        README.md                   # invocation + .k4k snippet to plug it in
    verifiers/
      dune-ocaml/                   # reference verifier, conforms to wire protocol
        main.ml                     # standalone OCaml binary
        README.md                   # invocation + .k4k snippet to plug it in
  prompts/
    formalize.md                    # step 2 (active)
    gap-step.md                     # step 3 (active)
    kb-regen.md                     # step 4 (wired but inactive — see ADR-007)
  test/
    unit/test_unit.ml               # one alcotest binary, modules per lib unit
    integration/test_integration.ml # S1 echo-upper end-to-end + smoke gates
    edge/test_edge.ml               # T-series boundary scenarios
  tests/fixtures/                   # *.k4k inputs + canned-responses JSON
  dune-project, k4k.opam, .gitignore
```

### Modules in `lib/` (each with paired `.mli` unless noted)

| Module                       | Purpose                                                                  |
|------------------------------|--------------------------------------------------------------------------|
| `error`                      | closed taxonomy, exit-code map                                           |
| `logger` (+ `Tty_status`)    | stderr text + `.k4k/log.jsonl`; in-place TTY status; secrets scrub       |
| `persist`                    | atomic tmp+fsync+rename, `.k4k/` init, fault-inject hook (NO `flock`; ADR-010 removed it) |
| `cotype`                     | wrapper around the `cotype` CLI for interaction-file safe-save (ADR-010) |
| `parser` (+ `_utf8`, `_frontmatter`, `_sections`) | YAML frontmatter + ownership-tag sections             |
| `manifest`                   | `Manifest.t` schema + atomic update                                      |
| `characterization` (+ `_json`, `_decoder`) | `Characterization.t` data type + hand-written codecs       |
| `canonical_json`             | byte-deterministic JSON serializer (sorted keys, no whitespace)          |
| `canonicalize`               | the determinism boundary (ADR-005): idempotent, equivalence-preserving   |
| `permissive_json`            | strip code fences, tolerate trailing prose (R7 from context-economy)     |
| `coverage`                   | `cli` coverage checklist enforcement                                     |
| `property` (+ `_json`, `_id`) | `Property.t` data + JSON codec; `"P" || sha256(aspect_path)[:7]` IDs    |
| `divergence`                 | divergence reports for unequal canonical hashes                          |
| `prompts`                    | template loader (`{{var}}` substitution); on-disk-over-baked-in fallback |
| `stability`                  | structural + two-run formalization protocol + cache                      |
| `full_check`                 | orchestrator: structural → cache → formalization → coverage              |
| `subprocess`                 | `execvp`-based runner with timeout + signal-poll                         |
| `git`                        | git wrapper via `Subprocess` (no `Sys.command`); incl. `reset_hard` for v2 rewind |
| `gap_prompt`                 | gap-step prompt rendering                                                |
| `diff_extract`               | unified-diff extraction + JSON-preface validation                        |
| `gap_step`                   | one direct-commit iteration: prompt → diff → apply-on-tree → verify → commit-or-reset (ADR-013 §2 step 3) |
| `version`                    | per-version git lifecycle: branch / commit_accept / merge+tag / rollback (ADR-013 §2) |
| `version_loop`               | top-level per-version driver: gap construction, retries, finalize        |
| `version_finalize`           | audit-md + final manifest + version completion / rollback hand-off       |
| `version_persist`            | `.k4k/version/<n>/` filesystem I/O                                       |
| `backend_canned`             | test-only canned-response backend loaded from JSON via `K4K_STUB_RESPONSES` |
| `sigint`                     | `Atomic.t` flag + safe-point check (NF1)                                 |
| `convergence`                | terminator: gap empty → exit 0                                           |
| `run_loop`                   | top-level loop with `--max-steps`/`--budget`, ETA window                 |
| `kb_regen` (+ `kb_render`)   | incremental ownership-aware target-KB regeneration (deterministic — ADR-007) |
| `harness`                    | DI seam over `Agent_backend`/`Verifier`; constructed in `bin/main.ml`    |
| `agent_backend`              | `module type S` for agent backends                                       |
| `backend_stub`               | DI stub with Strong/Weak profiles + canned responses (Q3.3)              |
| `backend_external`           | the only production backend adapter — invokes a configured executable per `external/backend-protocol.md`, reads JSON result |
| `verifier`                   | `module type S` for verifiers (internal scaffolding only — see ADR-008)  |
| `verifier_stub`              | DI stub                                                                  |
| `verifier_external`          | the only production verifier adapter — invokes a configured executable per `external/verifier-protocol.md`, reads JSON result |

Several modules are split (e.g. `characterization` → 3 files; `parser` → 4 files; `kb_regen` → 2 files) solely to honor the 200-line cap from `conventions/code-style.md`. They form one logical module each. The `agent_backend` and `verifier` "signature modules" are `.ml` files containing only `module type S`; no `.mli` companion (idiomatic dune).

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
- `decisions/adr-007-deterministic-kb-regen.md`
- `decisions/adr-008-verifier-protocol.md`
- `decisions/adr-009-backend-protocol.md`
- `conventions/code-style.md`
- `conventions/error-handling.md`
- `runbooks/test-environment.md`
