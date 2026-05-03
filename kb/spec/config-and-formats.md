---
id: spec.config-and-formats
type: spec
summary: On-disk byte layouts — interaction-file (.k4k) format, .k4k/ directory tree, manifest, gap, characterization, agent-runs, verifier-runs.
domain: spec
last-updated: 2026-05-02
depends-on: [glossary, spec.data-model]
refines: []
related: [spec.algorithms, spec.api-contracts]
---

# Config and Formats

## One-liner

How every k4k entity is laid out on disk: bytes, paths, file formats, encodings.

## Scope

Serialization only. Schemas live in `data-model.md`; procedures that read/write these formats live in `algorithms.md`.

## Interaction file (`<name>.k4k`)

UTF-8 (no BOM; if a BOM is present, k4k strips it on read). Line endings: LF. Max size 10 MB; larger ⇒ unstable with `EFILE_TOO_LARGE`.

### Top-level structure

```
---
k4k:
  version: 1
  class: cli
  backend:
    command: ["./scripts/agent.sh"]    # required; per external/backend-protocol.md
    timeout_s: 300                     # optional; default 300
  verifier:
    command: ["./scripts/verify.sh"]   # required; per external/verifier-protocol.md
    timeout_s: 60                      # optional; default 60
  budget:
    soft_per_step: 100
    hard_per_invocation: 1000
  retention:
    agent_runs_keep: 50
    verifier_runs_keep: 50
---
# Project name (free-form heading, ignored by k4k)

<!-- k4k:owner=user begin id=goal -->
## Goal
... prose paragraph ...
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=inputs-outputs -->
## Inputs and outputs
- argv: ...
- stdin: ...
- stdout: ...
- stderr: ...
- exit codes: ...
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=errors -->
## Error taxonomy
- EBADARG when ...
- EIOFAIL when ...
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=fs -->
## File-system contract
... or "N/A: program does not touch the filesystem" ...
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=concurrency -->
## Concurrency
N/A
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=perf -->
## Performance bounds
N/A
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=examples-accept -->
## Acceptance examples
1. argv=["echo","hi"] stdin="" → stdout="hi\n" stderr="" exit=0
2. ...
3. ...
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=examples-refuse -->
## Refusing examples
1. argv=["--unknown-flag"] → error EBADARG, exit=1, stderr matches /unknown flag/
<!-- k4k:owner=user end -->

<!-- k4k:owner=user begin id=out-of-scope -->
## Out of scope
- ...
<!-- k4k:owner=user end -->

<!-- k4k:owner=k4k begin id=clarification-2026-05-02-093000 hash=<sha256> -->
... appended by k4k when stability fails; the user answers in place by re-typing
the section under <!-- k4k:owner=user --> tags, then re-runs k4k ...
<!-- k4k:owner=k4k end -->
```

### Frontmatter rules

- `k4k.version` is required. Unknown versions ⇒ `EVERSION` (`error-taxonomy.md`).
- `class` is required. v0 accepts only `cli`.
- `backend.command` is required (a non-empty list of strings). Missing or empty ⇒ `EUNSTABLE` with a clarification block naming the missing field.
- `backend.timeout_s` is optional; default 300. Must be a positive integer if present.
- `verifier.command` is required (a non-empty list of strings). Missing or empty ⇒ `EUNSTABLE` with a clarification block naming the missing field.
- `verifier.timeout_s` is optional; default 60. Must be a positive integer if present.
- `budget` and `retention` are optional; defaults from this file apply.

The CLI flags `--backend '<cmd>'` / `--backend-timeout N` override the backend frontmatter for one run; `--verifier '<cmd>'` / `--verifier-timeout N` override the verifier frontmatter. Overrides do not persist to the manifest.

### Section ownership rules

- Each `<!-- k4k:owner=X begin id=Y [hash=H] -->` must be paired with a matching `<!-- k4k:owner=X end -->`.
- IDs must be unique across the file.
- `hash=` is required when `owner=k4k`; ignored when `owner=user`. On read, k4k recomputes `hash` and on mismatch flips ownership to `user` (logs `OWNERSHIP_FLIP` event).
- k4k *never* writes inside an `owner=user` block. Attempting to do so is a panic (`EINVARIANT`).

### Required user-owned sections (per `cli` class)

`goal`, `inputs-outputs`, `errors`, `fs`, `concurrency`, `perf`, `examples-accept`, `examples-refuse`, `out-of-scope`. Section IDs are normative — the parser keys on them.

## `.k4k/` directory tree

```
.k4k/
  # operational state (k4k-managed)
  characterization/
    desired/
      spec.json                 # canonical AST (D)
      spec.md                   # human-readable mirror (owner=k4k)
    current/
      spec.json                 # canonical AST (S)
  gap/
    properties.json             # array of Property
  agent-runs/<id>/
    prompt.md                   # exact text sent to the agent
    response.md                 # raw response
    diff.patch                  # extracted unified diff (empty if N/A)
    verdict.json                # AgentRun (data-model.md)
  verifier-runs/<id>/
    stdout.log
    stderr.log
    result.json                 # VerifierRun.result
  manifest.json                 # Manifest (data-model.md)
  log.jsonl                     # one JSON object per state transition
  archive.tar.zst               # rotated agent-runs/verifier-runs (created on retention sweep)

  # derived KB for the target program (k4k-generated, agentic-dev-kit layout)
  INDEX.md
  GLOSSARY.md
  indexes/by-task.md
  domain/prd.md
  spec/{data-model,algorithms,api-contracts,config-and-formats,error-taxonomy,INDEX}.md
  properties/{functional,non-functional,edge-cases,INDEX}.md
  architecture/overview.md
  architecture/decisions/<adr-files>
  external/INDEX.md
  conventions/{code-style,error-handling,testing-strategy}.md
  runbooks/audit-checklist.md
  reports/audit-<timestamp>.md
```

All KB files under `.k4k/` carry `owner: k4k` frontmatter and a `content_hash`. The user may hand-edit (ownership flips); k4k will not regenerate user-owned files.

## Atomic writes

Every write to `.k4k/manifest.json` and `.k4k/gap/properties.json` follows the pattern:
1. Open `<path>.tmp` for write
2. Write content + `fsync(2)`
3. `rename(2)` `.tmp` over the canonical path
4. `fsync(2)` the parent directory

Same pattern for `.k4k/characterization/{desired,current}/spec.json`.

## File locking

`<file.k4k>` is `flock(2)`-locked (advisory, exclusive) for the duration of any write by k4k. Reads do not lock. The lock is released before any long-running agent or verifier call returns to the harness loop.

## JSONL log format (`.k4k/log.jsonl`)

One object per line:

```
{"ts":"2026-05-02T09:30:00.123Z","level":"info","event":"stability.start","run_id":"...","details":{...}}
```

Standard event names: `stability.start`, `stability.pass`, `stability.fail`, `gap-step.start`, `gap-step.accept`, `gap-step.reject`, `gap-step.blocked`, `kb-regen.start`, `kb-regen.complete`, `ownership.flip`, `budget.exhausted`, `verifier.error`, `agent.error`. Unknown events at `level: "warn"` are tolerated by readers.

## Agent notes

> **Atomicity discipline:** every persistent state change must be atomic at the filesystem level. Power loss in the middle of a write must leave `.k4k/` consistent. The Ralph Loop relies on this — a half-written manifest looks like progress, and progress is what stops the loop.
>
> **Section IDs are part of the contract.** Renaming `goal` to `objective` would invalidate every prior interaction file. If you ever need to evolve them, do so via `k4k.version` bump, not silent rename.

## Related files

- `spec.data-model` — what's *in* these files (types)
- `spec.algorithms` — *how* k4k reads/writes them (procedures, canonicalization, hashing)
- `properties.non-functional` — atomicity & durability invariants
