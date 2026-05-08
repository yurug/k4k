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
  class: cli         # what kind of program; v2 supports cli (more in v3+)
---
# Project name (free-form heading, ignored by k4k)

## Goal
... prose paragraph ...

## Inputs and outputs
- argv: ...
- stdin: ...
- stdout: ...
- stderr: ...
- exit codes: ...

## Error taxonomy
- EBADARG when ...
- EIOFAIL when ...

## File-system contract
... or "N/A: program does not touch the filesystem" ...

## Concurrency
N/A

## Performance bounds
N/A

## Acceptance examples
1. argv=["echo","hi"] stdin="" → stdout="hi\n" stderr="" exit=0
2. ...
3. ...

## Refusing examples
1. argv=["--unknown-flag"] → error EBADARG, exit=1, stderr matches /unknown flag/

## Out of scope
- ...

## k4k:status

(machine-managed. Records the current version, per-property statuses,
ETA, and the most-recent activity. The user reads this; the user does
NOT edit it directly except for the documented control directives.)

## k4k:version:1

(snapshotted by k4k when the spec stabilizes; immutable thereafter.
Records the formal characterization hash and the verification tier
chosen for each property.)

## k4k:clarification:2026-05-08-093000

(appended by k4k when stability fails; the user answers in place
by editing this section freely. cotype's 3-way merge handles the
concurrency. See `external/cotype.md` and ADR-010.)

## k4k:tradeoff:proposal:2026-05-08-104500

(appended by k4k when Tier-A formal verification fails for a property
and a degradation to Tier B or C is proposed. The user reads, then
either edits the section to add `Approved: Tier B` (or rejects), and
re-saves. k4k waits for sign-off before proceeding at the degraded
tier. See `domain/prd.md` for the full tier hierarchy.)
```

### Frontmatter rules (v2)

- `k4k.version` is required. Unknown versions ⇒ `EVERSION` (`error-taxonomy.md`).
- `class` is required. v2 accepts only `cli`.
- **No tooling configuration is exposed to the user.** The frontmatter has only `k4k.version` and `class`; k4k self-selects the verifier, backend, and timeouts based on the formalized characterization and the host environment. (See `domain/prd.md` for the autonomous-agent UX and ADR-011 — when authored — for tier-aware tool selection.)

### Section identification

- The interaction file is parsed by Markdown headings (`##`).
- Each H2 heading delimits one section; section identity is derived by *normalizing* the heading text (lowercase, replace runs of non-alphanumeric chars with `-`, trim trailing `-`). E.g. `## Inputs and outputs` → `inputs-and-outputs`; `## File-system contract` → `file-system-contract`.
- A section heading matching one of the patterns below is **k4k-managed**. All other H2 sections are user-owned.
  - `## k4k:status` — the live status block (one per file, replaced by k4k each update).
  - `## k4k:version:<n>` — version snapshot (one per completed-or-in-flight version, accumulating over time).
  - `## k4k:clarification:<timestamp>` — clarification questions during instability.
  - `## k4k:tradeoff:proposal:<timestamp>` — Tier-A→B/C trade-off proposals; the user replies inline.
- HTML ownership tags from ADR-002 (`<!-- k4k:owner=... -->`) are ignored by the parser (treated as plain HTML comments) — see ADR-010. Old fixtures with the tags still parse; the tags are inert.

### Concurrency

User and k4k may both write to the file. **All writes from k4k go through `cotype`** (see `external/cotype.md` and ADR-010). The user installs cotype as a runtime dependency (`pipx install cotype`); k4k's `lib/cotype.ml` wraps the CLI per cotype's "Caller protocols → Agent / process" pattern. k4k never reads the interaction file's bytes directly — it reads from `cotype open`'s `base_path` and writes via `cotype save --base-sha`.

The structural-splicing recipe k4k uses (per cotype's docs and ADR-010) preserves user-owned sections byte-for-byte: when k4k writes, it copies all non-`k4k:clarification:*` sections from `base_path` unchanged, and only rewrites the k4k-managed sections. User vs k4k edits are non-overlapping by construction; `cotype save` returns `direct` or `merged` in normal operation, and `conflict` only when the user explicitly edited a `## k4k:clarification:*` section.

### Required user-owned sections (per `cli` class)

`goal`, `inputs-and-outputs`, `error-taxonomy`, `file-system-contract`, `concurrency`, `performance-bounds`, `acceptance-examples`, `refusing-examples`, `out-of-scope`. Section IDs are normative (derived by the heading-normalization rule above) — the parser keys on them.

## `.k4k/` directory tree

```
.k4k/
  # operational state (k4k-managed)
  characterization/
    desired/
      spec.json                 # canonical AST (D)
      spec.md                   # human-readable mirror, k4k-generated
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

Per ADR-010, k4k delegates interaction-file concurrency to `cotype`. cotype holds an exclusive `flock` on its sidecar (`.<basename>.cotype/lock`) for the duration of any mutating command — k4k itself does not call `flock`. The k4k wrapper (`lib/cotype.ml`) shells out to `cotype open` / `cotype save` and gets concurrency safety transparently. See `external/cotype.md`.

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
