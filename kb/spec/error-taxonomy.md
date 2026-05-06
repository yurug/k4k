---
id: spec.error-taxonomy
type: spec
summary: Every error k4k can produce — id, when raised, exit code, user-visible message, recovery hint. The closed set; new errors require a KB update.
domain: spec
last-updated: 2026-05-02
depends-on: [glossary, spec.algorithms, spec.api-contracts]
refines: []
related: [conventions.error-handling, properties.functional]
---

# Error Taxonomy

## One-liner

The exhaustive list of errors k4k may emit. Adding a new error type is a KB-first change: extend this file, then update `conventions/error-handling.md` and the relevant code.

## Scope

User-visible errors (exit codes, stderr messages) plus internal panics. Not for: log lines, audit-report findings.

## Exit-code map

| Code | Class                    | Meaning                                                                  |
|------|--------------------------|--------------------------------------------------------------------------|
| 0    | success                  | Gap empty (run), file stable (`--check`), printed status (`--status`).   |
| 1    | user error               | Interaction file missing, unparseable, unstable, or class unsupported.   |
| 2    | verifier error           | Verifier could not be invoked, or returned an unrecoverable `Tool_error`.|
| 3    | agent backend error      | Backend unavailable, credentials missing, all retries exhausted.         |
| 4    | resource exhaustion      | `--max-steps` reached, hard budget cap reached, disk full.               |
| 5    | environment error        | `.k4k/` corrupt, on-disk schema mismatch, missing dependency.            |
| 64+  | reserved                 | Internal panic codes (see `EINVARIANT`).                                 |

## Error catalog

### EFILE_NOT_FOUND
- **Exit:** 1
- **When:** `<file.k4k>` does not exist or is not a regular file.
- **stderr:** `k4k: file not found: <path>`
- **Recovery:** Verify path; if relative, check current directory.

### EFILE_TOO_LARGE
- **Exit:** 1
- **When:** `<file.k4k>` is larger than 10 MB.
- **stderr:** `k4k: file too large: <size> bytes (max 10485760)`
- **Recovery:** Split the spec or simplify.

### EENCODING
- **Exit:** 1
- **When:** `<file.k4k>` is not valid UTF-8 (after BOM strip).
- **stderr:** `k4k: encoding error at byte <n>: invalid UTF-8 sequence`
- **Recovery:** Re-save as UTF-8.

### EFORMAT
- **Exit:** 1
- **When:** YAML frontmatter unparseable, duplicate normalized H2 section IDs, or other structural shape violations of the interaction file.
- **stderr:** `k4k: format error: <details with line:col>`
- **Recovery:** Fix the structural issue cited.

### EVERSION
- **Exit:** 1
- **When:** `k4k.version` in frontmatter is unknown to this build of k4k.
- **stderr:** `k4k: unsupported version: <n> (this k4k handles versions 1..N)`
- **Recovery:** Upgrade k4k or downgrade `version` in frontmatter.

### ECLASS_UNSUPPORTED
- **Exit:** 1
- **When:** `class:` in frontmatter is not `cli` (v0).
- **stderr:** `k4k: unsupported class: <name> (v0 supports: cli)`
- **Recovery:** Set `class: cli` or wait for v1.

### EUNSTABLE
- **Exit:** 1
- **When:** Stability check fails (structural, semantic, or coverage). A clarification block is appended to the interaction file before exit.
- **stderr:** `k4k: unstable: <one-line summary>; see clarifications appended to <file.k4k>`
- **Recovery:** Open the file, answer the appended questions by editing the `## k4k:clarification:*` section directly (cotype handles the concurrency), re-run.

### EBUDGET
- **Exit:** 4
- **When:** Hard budget cap reached during a run (formalization or gap-step).
- **stderr:** `k4k: budget exhausted: <used>/<cap> units; .k4k/ left consistent`
- **Recovery:** Increase `k4k.budget.hard_per_invocation` in frontmatter, or split the work across runs.

### EMAXSTEPS
- **Exit:** 4
- **When:** `--max-steps N` reached before `G` is empty.
- **stderr:** `k4k: max steps reached (<N>); <gap_size> properties remain`
- **Recovery:** Re-run; or raise `--max-steps`.

### EAGENT_UNAVAILABLE
- **Exit:** 3
- **When:** Agent backend cannot be reached (binary missing, network down, auth failure). All retries exhausted.
- **stderr:** `k4k: agent backend <name> unavailable: <details>`
- **Recovery:** Check `$ANTHROPIC_API_KEY` / `claude` binary on `$PATH`; check network.

### EVERIFIER_UNAVAILABLE
- **Exit:** 2
- **When:** Verifier binary missing on `$PATH`, or first invocation fails before a result file is written.
- **stderr:** `k4k: verifier <name> unavailable: <details>`
- **Recovery:** Install the toolchain (e.g. `opam install dune`).

### EVERIFIER_TOOL_ERROR
- **Exit:** 2
- **When:** Verifier returned `Tool_error`. Logs are at `.k4k/verifier-runs/<id>/`.
- **stderr:** `k4k: verifier error: <details>; see .k4k/verifier-runs/<id>/`
- **Recovery:** Inspect the logs; fix the underlying tool issue.

### EDISK_FULL
- **Exit:** 4
- **When:** A write to `.k4k/` failed with `ENOSPC` (or equivalent). State is rolled back.
- **stderr:** `k4k: disk full while writing <path>; rolled back`
- **Recovery:** Free space; re-run.

### ESTATE_CORRUPT
- **Exit:** 5
- **When:** `.k4k/manifest.json` exists but is unparseable or version-mismatched.
- **stderr:** `k4k: state corrupt: <details>; consider --reset`
- **Recovery:** Inspect manifest; if irrecoverable, `k4k --reset`.

### EOWNERSHIP_VIOLATION
- **Exit:** 64 (panic)
- **When:** Internal invariant — k4k attempted to write inside an `owner=user` region.
- **stderr:** `k4k: BUG: ownership violation at <path>:<line>; please report`
- **Recovery:** None at runtime; this is a code bug.

### EINVARIANT
- **Exit:** 64+ (panic)
- **When:** Any internal invariant violation not covered above.
- **stderr:** `k4k: BUG: <message>; please report`
- **Recovery:** None.

## How errors are emitted

- All user-visible errors go to **stderr**, one line, `k4k: <message>` prefix.
- All errors trigger a `level: "error"` JSONL log entry with `code` and `details`.
- Panics (exit 64+) additionally write a stack trace to `.k4k/log.jsonl` (truncated at 8 KB per entry).

## Agent notes

> **Closed set.** Code that throws an exception not in this catalog is buggy. Use `conventions/error-handling.md`'s typed error hierarchy; every variant maps to one ID here.
>
> **No silent failures.** A `Tool_error` from the agent or verifier *always* maps to a non-zero exit and a clarification or log entry. The Ralph Loop relies on negative signal being loud.

## Related files

- `conventions/error-handling.md` — typed error hierarchy in OCaml; how each ID is raised
- `properties/functional.md` — `P.error-taxonomy-closed` invariant
- `spec/algorithms.md` — points where these errors fire
