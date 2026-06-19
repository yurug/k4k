---
id: architecture.overview
type: concept
summary: Module structure, dependency graph, and DI surface for the v2 watcher daemon. The wiring diagram from `bin/main.ml` down to backend/verifier executables.
domain: architecture
last-updated: 2026-05-08
depends-on: [glossary, spec.api-contracts, spec.algorithms]
refines: []
related: [architecture.decisions.index, conventions.code-style, conventions.error-handling]
---

# Architecture Overview

> **v2 — partially superseded (2026-06-19).** This describes the v2 watcher-daemon + cotype wiring. The v3 reorientation (ADR-014/015/016) keeps the **harness core** documented here — `Gap_step` propose/accept-or-reject, the verifier/backend wire protocols, branch-per-version (ADR-013), extraction — but removes the cotype layer and the in-file orchestration (`Watcher_loop` polling, `Status_splice`, `Watcher_prune`, `Version_user_edits`) and replaces the prose→formal two-run formalization with a static stability check on k4kspec. Read alongside the v3 ADRs; this file will be re-synced when the v3 surface is built.

## One-liner

k4k is a small OCaml CLI organized as a deterministic watcher daemon
(ADR-011) wrapping two pluggable interfaces (agent backend, verifier)
plus one hardcoded runtime dependency (cotype, ADR-010). Every agent
call, verifier call, and on-disk write goes through a typed seam so
the test suite runs against in-memory canned fixtures.

## Scope

How the modules in `bin/` and `lib/` are wired in v2. *Why* the
choices are this way lives in `decisions/`. *What* each module does
(procedures, types) lives in `spec/`.

## Top-level module graph

```
                        ┌────────────────────────────────┐
                        │  bin/main.ml (cmdliner entry)  │
                        └────────────────┬───────────────┘
                                         │  argv parsing only;
                                         │  hands off to Watcher.run
                                         ▼
   ┌────────────────────────────────────────────────────────────────┐
   │                       lib/Watcher                              │
   │  - startup phase (file/git/cotype/toolchain checks, PID acq.)  │
   │  - emit_event closure (JSONL stdout, stderr verbosity tiers)   │
   │  - typify_startup_exception (Unix_error → typed K4k_error)     │
   └────────────────┬───────────────────────────────────────────────┘
                    │ Watcher_loop.run with shared agent_invoke
                    ▼
   ┌────────────────────────────────────────────────────────────────┐
   │                     lib/Watcher_loop                           │
   │  - poll cotype at 2 Hz; parse user directives                  │
   │  - dispatch on stability                                       │
   │  - terminal-version counter for --exit-on-done / --max-versions│
   └────┬─────────────────┬──────────────────┬─────────────────┬────┘
        │                 │                  │                 │
        │ unstable        │ stable, prune    │ stable, drive   │ rollback
        ▼                 ▼                  ▼                 ▼
   ┌─────────┐   ┌──────────────────┐ ┌──────────────────┐ ┌──────────┐
   │  Cotype │   │ Watcher_prune    │ │ Watcher_dev      │ │ Version. │
   │ append_ │   │ (ADR-011 §7)     │ │ (try_run_version)│ │ rollback │
   │ clarif. │   └──────────────────┘ └────┬─────────────┘ └──────────┘
   └─────────┘                             │
                                           ▼
                            ┌──────────────────────────────┐
                            │ Watcher_form  (formalization)│
                            │ Backend_resolve.resolve      │
                            │  → Backend_canned (test)     │
                            │  → Backend_external (prod)   │
                            │  → unconfigured fallback     │
                            └────┬─────────────────────────┘
                                 │ Ok d
                                 ▼
                            ┌──────────────────────────────┐
                            │       lib/Version_loop       │
                            │  - drive_version on branch   │
                            │  - run_gap_loop              │
                            │  - per-iteration             │
                            │    Version_user_edits.check  │
                            │  - 3-strikes → Tradeoff      │
                            │  - drive_property_full       │
                            └────┬───────────┬─────────────┘
                                 │           │
                                 │ Tradeoff  │ Accepted/Rejected
                                 ▼           ▼
                ┌──────────────────────────┐  ┌──────────────────────────┐
                │     lib/Version_tradeoff │  │      lib/Gap_step        │
                │   propose / wait / drive │  │  preflight (clean tree,  │
                │   at approved tier       │  │  Diff_filter), agent     │
                │  via Tradeoff_flow       │  │  call, verifier focus,   │
                └────────────┬─────────────┘  │  commit_accept / reset   │
                             │                 └────────────┬─────────────┘
                             ▼                              │
                ┌──────────────────────────┐                │
                │     lib/Tradeoff_flow    │                │
                │  splice proposal block,  │                │
                │  poll cotype for reply,  │                │
                │  archive + breadcrumb    │                │
                └──────────────────────────┘                │
                                                            ▼
                                          ┌──────────────────────────────┐
                                          │  Verifier_external           │
                                          │  (subprocess via Subprocess) │
                                          └──────────────────────────────┘

  At loop end:  Version_finalize.finalize → audit.md + git merge + git tag
                (or Rolled_back; the version branch persists for audit)
```

`Persist` is a peer of every writing module: atomic tmp+fsync+rename,
the only handle to `.k4k/`. The interaction file (`<file.k4k>`) is
NEVER written by `Persist` — that surface goes through `lib/Cotype`
(per ADR-010), which delegates to the `cotype` CLI.

`Canonicalize` is a pure library used by `Watcher_form` and
indirectly by `Gap_step` (via the property-id derivation in
`Property.from_characterization`).

## v2 module map

The list below is the actual current `lib/` tree. Modules are
grouped by what they own; each group's lead module is the public
entry; the rest are extracted helpers (kept ≤ 200 lines per the
code-style cap).

### Watcher orchestration (ADR-011 / ADR-013)

| Module                       | Owns                                                               |
|------------------------------|--------------------------------------------------------------------|
| `watcher`                    | startup (file/git/cotype/toolchain/PID), `emit_event`, exception typification |
| `watcher_loop`               | the polling loop body: directives → stability dispatch → exit gates |
| `watcher_dev`                | the development half: formalize → idempotence gate → dispatch_one  |
| `watcher_form`               | two-run formalization driver + per-top-level-manifest persistence   |
| `watcher_pid`                | `.k4k/watcher.pid` single-instance enforcement (ADR-011 §2)         |
| `watcher_prune`              | welcome auto-delete + clarification/tradeoff archival (ADR-011 §7)  |
| `backend_resolve`            | `agent_invoke` resolution: K4K_STUB_RESPONSES → K4K_BACKEND_COMMAND → unconfigured fallback |
| `starter_template`           | first-run starter `.k4k` body + `auto_frontmatter` injector         |
| `inline_blocks`, `inline_blocks_sections` | renderers + parsers for the four ADR-011 in-file blocks |
| `status_splice`              | line-oriented `## k4k:status` replace-or-append (no parser dep)     |

### Per-version state machine (ADR-013)

| Module                       | Owns                                                                |
|------------------------------|---------------------------------------------------------------------|
| `version`                    | git lifecycle: `start_new`, `commit_accept`, `complete` (merge+tag), `rollback` |
| `version_loop`               | top-level per-version driver: gap, retries, finalize hand-off       |
| `version_finalize`           | audit-md + per-version manifest + Done/Rolled_back hand-off         |
| `version_persist`            | `.k4k/version/<n>/` filesystem I/O                                  |
| `version_tradeoff`           | propose-and-wait + drive-at-tier on Approved/Rejected/Timed_out     |
| `version_user_edits`         | P22: snapshot baseline hashes; `check_and_queue` between iterations |
| `tradeoff_flow`              | `## k4k:tradeoff:proposal:<ts>` splice, polling, archive + breadcrumb|
| `clarification`              | append-clarification helpers (ADR-010 conflict propagation)         |

### Gap-step engine (ADR-013 §2 step 3)

| Module                       | Owns                                                                |
|------------------------------|---------------------------------------------------------------------|
| `gap_step`                   | one direct-commit iteration: preflight → prompt → agent → diff_filter → apply → verify → commit/reset |
| `gap_prompt`                 | tier-aware prompt rendering (`prompts/gap-step.tier-{a,b,c}.md`)    |
| `diff_filter`                | path-allowlist for unified diffs (rejects `.k4k/`, `.git/`, abs, `..`) |
| `diff_extract`               | unified-diff extraction + JSON-preface validation                   |
| `audit_md`                   | per-version `audit.md` Markdown renderer                            |

### Pluggable interfaces (ADR-008/009/012)

| Module                       | Owns                                                                |
|------------------------------|---------------------------------------------------------------------|
| `agent_backend`              | `module type S` + `purpose` / `result` types                        |
| `backend_external` (+ `_parse`) | production adapter: invokes a configured executable per `external/backend-protocol.md` |
| `backend_canned`             | test-only canned-response loader (`K4K_STUB_RESPONSES`)             |
| `backend_stub`               | test-only minimal in-memory stub (Strong/Weak profiles for NF8)     |
| `verifier`                   | `module type S` + `result_ok` / `run_result` types                  |
| `verifier_external` (+ `_parse`) | production adapter: invokes a configured executable per `external/verifier-protocol.md` |
| `verifier_stub`              | test-only deterministic adapter                                     |
| `cotype` (+ `_parse`, `_stub`) | wrapper around the `cotype` CLI for interaction-file safe-save (ADR-010) |
| `toolchain_install`          | `ensure ~binary` (cotype, git): probes `$PATH`, opt-in user-scoped install |

### Pure libraries

| Module                       | Owns                                                                |
|------------------------------|---------------------------------------------------------------------|
| `parser` (+ `_utf8`, `_frontmatter`, `_sections`) | structural parse: H2 sections + minimal frontmatter (ADR-011 §1: only `version` + `class`) |
| `characterization` (+ `_json`, `_decoder`) | `Characterization.t` data type + hand-written codecs incl. `language` + `verifier_command` (ADR-012 §1) |
| `canonicalize`               | the determinism boundary (ADR-005): idempotent, equivalence-preserving |
| `canonical_json`             | byte-deterministic JSON serializer (sorted keys, no whitespace)     |
| `permissive_json`            | tolerate code-fence wrappers and trailing prose (R7 from context-economy) |
| `coverage`                   | `cli` coverage checklist enforcement                                 |
| `property` (+ `_json`, `_id`) | `Property.t` + `"P" || sha256(aspect_path)[:7]` IDs                |
| `divergence`                 | divergence reports for unequal canonical hashes                      |
| `prompts`                    | template loader (`{{var}}` substitution); on-disk-over-baked-in fallback |
| `stability`                  | structural + two-run formalization protocol + cache                  |
| `kb_regen` (+ `kb_render`)   | incremental ownership-aware target-KB regeneration (ADR-007)         |

### I/O + plumbing

| Module                       | Owns                                                                |
|------------------------------|---------------------------------------------------------------------|
| `persist`                    | atomic tmp+fsync+rename, `.k4k/` init, NF4 trace hook                |
| `logger` (+ `Tty_status`)    | `.k4k/log.jsonl` + secrets scrub; the v2 watcher emits via `cfg.emit` rather than `Logger.stdout_line` |
| `subprocess`                 | `execvp`-based runner with timeout + signal-poll (no `Sys.command`)  |
| `git`                        | git wrapper via `Subprocess`; `apply_diff` calls `Diff_filter.first_forbidden` first |
| `manifest`                   | top-level `.k4k/manifest.json` schema + atomic update                |
| `error`                      | closed taxonomy + exit-code map (16 variants)                        |
| `sigint`                     | `Atomic.t` flag + safe-point check (NF1 ≤ 5s shutdown latency)       |

## Dependency injection

The DI seam is the `agent_invoke` and `verifier_run` closures threaded
through `Version_loop.config`. Both are allocated ONCE per watcher
run (the canned backend's per-purpose queues must persist across
iterations, audit-2026-05-08 batch 5 H-3) and reused.

```ocaml
(* lib/watcher_loop.ml — abridged *)
let run cfg : int =
  ...
  let agent_invoke = Watcher_dev.resolve_invoke ~emit:cfg.emit in
  let rec loop () =
    match one_tick cfg ct ~stable_seen:!stable ~versions_done
            ~agent_invoke with
    | `Stop -> ()
    | `Continue s -> stable := s; loop ()
  in
  loop ()
```

Inside `Watcher_dev.dispatch_one`, the closures land in
`Version_loop.config`:

```ocaml
let v_cfg : Version_loop.config = {
  ...
  agent_invoke;                                 (* shared *)
  verifier_run = verifier_invoke ~k4k_dir ~d;   (* fresh per version *)
  ...
}
```

`Backend_resolve.resolve` picks one of three paths at startup
(`K4K_STUB_RESPONSES` → canned, `K4K_BACKEND_COMMAND` → external,
otherwise unconfigured-fallback). `verifier_invoke` always uses
`Verifier_external` configured with the agent-supplied
`Characterization.verifier_command` (ADR-012 §1).

No global state. No `Sys.getenv` outside `bin/main.ml`,
`Backend_resolve`, and `Persist`'s NF4 trace hook.

## Error hierarchy (OCaml)

```ocaml
(* lib/error.ml *)
type error =
  | E_format               of { line : int; col : int; reason : string }
  | E_unstable             of issue list
  | E_version              of { found : int; supported : int list }
  | E_class_unsupported    of string
  | E_budget               of { used : int; cap : int }
  | E_max_steps            of int
  | E_agent_unavailable    of string
  | E_verifier_unavailable of string
  | E_verifier_tool_error  of string
  | E_disk_full            of string
  | E_state_corrupt        of string
  | E_encoding             of int
  | E_file_not_found       of string
  | E_file_too_large       of int
  | E_ownership_violation  of string  (* exit 64; cotype declined to merge *)
  | E_internal_panic       of string  (* exit 64; uncaught exception *)

exception K4k_error of error
exception Invariant_violation of string   (* legacy; superseded by E_internal_panic *)
```

Exit-code mapping in `Error.exit_code_of`: 1 (user/spec) | 2
(verifier) | 3 (agent) | 4 (resource) | 5 (state/PID) | 64
(panic). The cmdliner `Cmd.info ~exits` block in `bin/main.ml`
mirrors this so `--help` shows our codes, not cmdliner's defaults
(123/124/125).

`Watcher.startup` typifies bare `Unix.Unix_error` from mkdir/open
into `E_state_corrupt` so the closed taxonomy holds across the
startup boundary.

## File layout (current)

```
k4k/
  bin/main.ml                       # cmdliner entry; hands off to Watcher.run
  lib/                              # 51 modules (see groups above)
  examples/
    backends/
      claude-code/                  # reference backend, conforms to ADR-009
        main.ml
        smoke.sh                    # opt-in live smoke against `claude` CLI
        README.md
      ollama/                       # second reference backend
  prompts/
    formalize.md
    gap-step.tier-{a,b,c}.md
    kb-regen.md
  test/
    unit/test_unit.ml               # one alcotest binary (~240 cases)
    integration/test_integration.ml # ~22 cases incl. S1, S3, P22, P22b
    edge/test_edge.ml               # T-series boundary scenarios
    conformance/                    # 6 wire-protocol-conformance tests
      fixtures/synthetic-verifier.sh
  tests/fixtures/                   # *.k4k inputs + canned-responses JSON
  dune-project, k4k.opam, .gitignore
```

`examples/verifiers/` was removed in batch 2's cleanup — per
ADR-012, the agent emits the verifier wrapper per project; k4k
ships no reference verifier example.

## Invariants enforced architecturally

- **No I/O outside `Persist` and `Cotype`** (except: agent and
  verifier modules' I/O to external processes; `Logger` writing to
  stderr / `.k4k/log.jsonl`; `Watcher` writing the JSONL event
  stream to stdout via `print_endline`).
- **No global state.** Every module exposes `type t` or pure
  functions; the DI seam is constructed in `Watcher_loop.run`.
- **No raise outside `Error.K4k_error`** in user-visible paths;
  uncaught exceptions are typified to `E_internal_panic` at the
  watcher boundary.
- **Files ≤ 200 lines, functions ≤ 30 lines.** Hard limit;
  enforced by convention and audited by axis 6.
- **No agent-text in conditionals.** Every state transition reads
  off `Verifier.result_ok` / `prev_status` / `failure_count` /
  `budget_remaining` only.
- **Diff path-filter before any agent diff is applied.**
  `Git.apply_diff` calls `Diff_filter.first_forbidden`; rejection
  returns `Error` *before* any FS write (audit-2026-05-08 axis 2 H1).

## Agent notes

> **One DI surface.** Adding a backend or verifier should not touch
> `Watcher_loop`, `Version_loop`, or `Gap_step`. New backends conform
> to `kb/external/backend-protocol.md` and plug in via
> `Backend_external` + `K4K_BACKEND_COMMAND` (or
> `K4K_STUB_RESPONSES` for tests). New verifiers conform to
> `kb/external/verifier-protocol.md` and arrive via the
> `Characterization.verifier_command` field the agent emits per
> ADR-012.
>
> **Pure where possible.** `Canonicalize`, `Parser`, `Diff_filter`,
> `Inline_blocks`, `Status_splice`, `Audit_md`, `Coverage`,
> `Property_id` are pure. The test suite leans heavily on this.

## Related files

- `decisions/adr-008-verifier-protocol.md`, `adr-009-backend-protocol.md`
- `decisions/adr-010-cotype-delegation.md`
- `decisions/adr-011-autonomous-agent-ux.md`
- `decisions/adr-012-agent-driven-toolchain.md`
- `decisions/adr-013-version-as-git-branch.md`
- `conventions/code-style.md`, `conventions/error-handling.md`
- `runbooks/test-environment.md`, `runbooks/audit-checklist.md`
- `kb/reports/audit-2026-05-08-summary.md` — the audit that drove
  the v0→v2 module-graph cleanup
