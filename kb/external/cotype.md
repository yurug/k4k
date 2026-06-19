---
id: external.cotype
type: external
summary: Runtime dependency. cotype provides safe-save concurrency for the interaction file (user + k4k editing the same `.k4k` file). Hardcoded — like git — not a pluggable wire protocol.
domain: external
last-updated: 2026-05-03
depends-on: [glossary, spec.config-and-formats, spec.algorithms]
refines: []
related: [adr-010, adr-002]
---

# External: cotype

> **SUPERSEDED in v3 (2026-06-19, ADR-014).** k4k no longer depends on cotype. The v3 propose/review model gives the spec a single writer (the human), so there is no concurrent-edit problem to delegate. `lib/cotype*` and the runtime dependency are dropped. This contract is retained only for history. See ADR-014 and `domain/prd.md`.

## One-liner

A small CLI that provides 3-way-merge concurrency on a single text file (`<https://pypi.org/project/cotype/>`). k4k uses it to coordinate user + agent edits to the interaction file without lost updates, replacing k4k's hand-rolled ownership-tag scheme. **Like git, cotype is a hardcoded runtime dependency** — not a pluggable wire protocol.

## Why we depend on it (per ADR-010)

The interaction file is the user's contract with k4k. Both the user and k4k write to it:
- The user authors the spec and edits answers to clarification questions.
- k4k appends clarification blocks when stability fails.

Pre-ADR-010, k4k coordinated this via in-document ownership tags (`<!-- k4k:owner=user/k4k -->` + content hashes) and `flock(2)`. cotype solves the same problem with a cleaner model (3-way merge over `diff3`, optimistic concurrency) and is independently maintained — k4k delegating is the same architectural move as ADR-008/009 (verifier/backend retrofits) applied to the user-agent file protocol.

## Install requirement

The user installs cotype before running k4k. Recommended:

```bash
pipx install cotype     # isolated Python install
# or
pip install cotype       # in your active venv
```

Requires **Python ≥ 3.11** and **POSIX `diff3`** (from `diffutils` — almost always already installed on Linux/macOS). k4k checks for `cotype` on `$PATH` at startup; missing → `EVERIFIER_UNAVAILABLE`-class error with a hint to install.

## CLI surface (the parts we use)

```text
cotype init     FILE [--json]                    # idempotent; create sidecar
cotype open     FILE [--json]                    # capture base snapshot; returns base_sha + base_path
cotype save     FILE --base-sha HASH [--actor X] [--json]   # propose new bytes via stdin
cotype status   FILE [--json]                    # unmanaged / clean / conflicted
cotype resolve  FILE [--actor X] [--json]        # clear a pending conflict (after user resolves diff3 markers)
cotype cat-base FILE [--base-sha HASH]           # print a base snapshot (debugging)
```

k4k always passes `--json` and parses the JSON envelope. `--actor agent:k4k` labels every k4k-side `save` for the conflict metadata.

## Sidecar layout

cotype creates a sidecar directory next to FILE:
```
.<basename>.cotype/
  base/<sha>            # base snapshots
  conflicts/<id>/       # forensic three-way copies for diagnostics
  lock                  # flock target (cotype's internal concurrency control)
```

For `myproject.k4k` the sidecar is `.myproject.k4k.cotype/`. This is **separate from k4k's own `.k4k/`** operational dir — both coexist in the user's project directory. The `.gitignore` snippet k4k provides excludes both.

## The protocol k4k follows

Every k4k-side mutation of the interaction file follows this sequence (per cotype's "Caller protocols → Agent / process"):

```
1.  meta = cotype open FILE --json
2.  base_sha  = meta.base_sha
3.  base_path = meta.base_path
4.  src       = read(base_path)              # NEVER read FILE directly
5.  proposed  = splice_k4k_managed_sections(src, ...)
6.  result    = cotype save FILE --base-sha base_sha --actor agent:k4k
                  --json < proposed
7.  case result.status:
    saved    -> done; record result.sha if needed
    conflict -> log the conflict file path, surface to user, exit 5
```

**Step 4 is critical.** Reading directly from FILE (instead of `base_path`) defeats cotype's merge bookkeeping — a concurrent writer's bytes would sneak into our "what I edited from" without cotype noticing. The k4k wrapper in `lib/cotype.ml` enforces the discipline.

### Structural splicing — recommended by cotype, naturally fitting k4k

cotype's documentation explicitly recommends parsing the file into structured regions and rewriting only the actor's own region; everything else flows through unchanged from `base_path`. Two actors editing two different regions then cannot conflict by construction.

For k4k:
- The interaction file is parsed by Markdown headers.
- k4k-managed sections are identified by a stable heading pattern: `## k4k:clarification:<timestamp>` (the only sections k4k writes).
- All other sections (`## Goal`, `## Inputs and outputs`, …) are user-owned.
- When k4k splices, it copies all non-k4k-managed sections byte-for-byte from `base_path` and only rewrites/appends `## k4k:clarification:*` blocks.

This makes user vs k4k edits non-overlapping by construction, so cotype's diff3 merge will produce `direct` or `merged` outcomes nearly always. A `conflict` outcome means the user edited a `## k4k:clarification:*` section directly, which is the user explicitly taking ownership of that block — same semantics as the old "ownership flip", now without an in-document tag.

## Exit-code mapping

| cotype exit | meaning                          | k4k action                                     |
|-------------|----------------------------------|------------------------------------------------|
| 0           | success                          | continue                                       |
| 1           | merge conflict                   | exit 5 with `ESTATE_CORRUPT`-class message + path to conflicted file |
| 2           | usage error                      | exit 64 (panic; bug in `lib/cotype.ml`)        |
| 3           | unmanaged / corrupt sidecar      | run `cotype init` (auto-recovery) or exit 5    |
| 4           | unknown base                     | exit 5 (state corrupt; suggest `--reset`)      |
| 5           | pending conflict (resolve first) | exit 5 with hint to run `cotype resolve` after editing out the diff3 markers |
| 6           | I/O error                        | exit 4 (`EDISK_FULL` family)                   |
| 7           | merge tool error                 | exit 5 (sidecar / diff3 invocation broke)      |

## Stable error names (in `--json` envelope)

`UsageError | UnsupportedFile | UnmanagedFile | CorruptSidecar | UnknownBase | ConflictPending | IoError | MergeToolError | InvalidUtf8`. k4k's wrapper maps each to one of the above k4k-side exit codes; the stable error name appears in `.k4k/log.jsonl` for forensics.

## Determinism

`cotype save` is deterministic given identical bytes and base — same input produces same output. No external network. The merge step shells out to POSIX `diff3 -m`, which is itself deterministic. k4k's `NF6` (system-level determinism) extends naturally to cotype-mediated writes.

## Side effects

- Creates `.<basename>.cotype/` next to FILE.
- Holds an exclusive `flock` on `<sidecar>/lock` for the duration of any mutating command. (This means k4k's old `Persist_lock` module — added in audit gap H2 — is obviated; cotype handles concurrency.)
- Writes to FILE go through tmp + fsync + rename + parent-fsync.

## Versioning

`cotype --version` is recorded in `manifest.cotype.version` on every k4k run. Major version bumps warrant a JSONL warning but do not invalidate state by themselves.

## Failure modes k4k must handle

| Failure                                       | Detection                                                      | k4k action                                          |
|-----------------------------------------------|----------------------------------------------------------------|-----------------------------------------------------|
| `cotype` not on `$PATH`                       | execvp ENOENT                                                   | exit 5 with hint `pipx install cotype`              |
| Python or `diff3` missing                     | cotype itself errors                                           | propagate cotype's stderr; exit 5                   |
| Sidecar absent on first run                   | `cotype open` returns `UnmanagedFile`                          | run `cotype init` automatically; retry              |
| Sidecar corrupt                               | cotype returns `CorruptSidecar`                                | exit 5 with hint to `--reset` or remove sidecar     |
| User-introduced merge conflict (diff3 markers in FILE) | `cotype status` → `conflicted`; subsequent `save` fails | exit 5 with the conflict path; tell the user to edit + run `cotype resolve` |

## Agent notes

> **Read `base_path`, never FILE.** This is the load-bearing rule. The OCaml wrapper centralizes this; downstream callers that bypass the wrapper to "just read the file" violate the contract.
>
> **`cotype init` is idempotent.** k4k may call it on every startup without bookkeeping; if the sidecar already exists, it's a no-op.
>
> **No privileged actor.** k4k passes `--actor agent:k4k` for tracing, but cotype gives no special treatment to k4k's writes vs. the user's. This is the right semantics — k4k is a peer to the user, not an authority.

## Related files

- `architecture/decisions/adr-010-cotype-delegation.md` — the decision record
- `architecture/decisions/adr-002-interaction-file-format.md` — partially superseded; ownership tags removed
- `properties/functional.md` — `P1` (ownership inviolability) now realized via cotype's protocol; `P12` (flock) superseded; `P13` (fresh-read) still applies but via `cotype open`; `P14` (ownership-flip detection) superseded by cotype's conflict outcome
- `spec/config-and-formats.md` — interaction file format simplified (no ownership tags)
- `spec/algorithms.md` — `#ownership` and `#concurrent-edits` sections rewritten in terms of cotype
