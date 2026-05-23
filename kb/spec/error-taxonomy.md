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

The exhaustive list of error conditions k4k may surface. In v2 the user does not see exit codes — the watcher reports state changes through the `.k4k` file (status/clarification/tradeoff blocks per `config-and-formats.md`). The codes below apply to the *startup phase only* (the brief moment between `k4k <file>` invocation and the watcher entering its main loop) and to operator-level diagnostics. Adding a new error type is a KB-first change: extend this file, then update `conventions/error-handling.md` and the relevant code.

## Scope

Conditions that prevent the watcher from starting cleanly OR that surface as in-file events once the watcher is running. Not for: log lines, audit-report findings.

## Exit-code map

The watcher's exit codes split into two regimes:

- **Startup phase**: `Watcher.startup` typifies any caught exception
  (including bare `Unix.Unix_error`) into the closed `Error.error`
  taxonomy and exits with the corresponding code.
- **Runtime phase** (post-startup, watcher loop active): the user
  does NOT see exit codes for normal events; the watcher reports
  state changes in the `.k4k` file via `## k4k:clarification:*` /
  `## k4k:tradeoff:proposal:*` / `## k4k:status` blocks. The runtime
  phase exits cleanly (0) on signal, on the test-only flags, or on
  a fatal verifier/agent unavailability that retries cannot
  recover.

| Code | Class                    | When it can fire                                                          |
|------|--------------------------|---------------------------------------------------------------------------|
| 0    | success                  | Graceful shutdown (signal, `--exit-on-stable`, `--exit-on-done`, `--max-versions`). |
| 1    | user / spec error        | `EFILE_NOT_FOUND`, `EFILE_TOO_LARGE`, `EENCODING`, `EFORMAT`, `EVERSION`, `ECLASS_UNSUPPORTED` — startup phase. |
| 2    | verifier                 | `EVERIFIER_UNAVAILABLE`, `EVERIFIER_TOOL_ERROR` — both phases (fatal after retries). |
| 3    | agent                    | `EAGENT_UNAVAILABLE` — both phases (fatal after retries). |
| 4    | resource exhaustion      | `EDISK_FULL` — both phases. (`EBUDGET` / `EMAXSTEPS` no longer surface as exit codes; see "Internal-only events" below.) |
| 5    | environment / state      | `ESTATE_CORRUPT`, `ETOOLCHAIN_UNAVAILABLE`, plus PID-collision (another live watcher already owns `.k4k/watcher.pid`). |
| 64   | ownership / invariant    | `EOWNERSHIP_VIOLATION`, `EINVARIANT` — panic path; full trace appended to `.k4k/log.jsonl` plus a "please report" message. |

**Internal-only events** (no longer exit codes, surface in-file once the watcher is running):

- Spec instability (semantic ambiguity, missing required sections, coverage gaps) → `## k4k:clarification:<ts>` block in the file.
- Per-property verifier rejection / 3-strikes-blocked → recorded in the `## k4k:status` block; if k4k cannot proceed, a `## k4k:tradeoff:proposal:<ts>` block.
- Tier-A failure on a property → trade-off proposal block in the file.
- Budget bookkeeping → tracked internally; surfaces as a status update or trade-off proposal, not an exit code.
- Verifier or backend tool errors → retried per protocol (`external/verifier-protocol.md`, `external/backend-protocol.md`); persistent failures surface as in-file diagnostics, not exit codes.

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
- **Exit:** *no longer an exit code in v2.* Spec instability is reported in-file as a `## k4k:clarification:<ts>` block. The watcher does NOT exit on instability; it pauses development (if any was in-flight) and waits for the user to edit the file. *(Pre-v2: this used to surface as exit 1.)*

### (removed in v2) EBUDGET / EMAXSTEPS
Budget and step bookkeeping are no longer user-visible exit codes. Budget exhaustion during development surfaces as a `## k4k:status` update and (if it blocks progress) a `## k4k:tradeoff:proposal:<ts>` block proposing how to proceed (e.g. "running out of budget on Tier A; propose decomposing the property into smaller lemmas, or dropping to Tier B"). The user replies inline.

### EAGENT_UNAVAILABLE
- **Exit:** 3
- **When:** Agent backend cannot be reached (binary missing, network down, auth failure). All retries exhausted.
- **stderr:** `k4k: agent backend unavailable: <details>; check that the backend binary is on $PATH and that any required credentials (e.g. ANTHROPIC_API_KEY) are set in the environment`
- **Recovery:** Above hint covers the common cases; see `.k4k/log.jsonl` for diagnostics.

### ETOOLCHAIN_UNAVAILABLE
- **Exit:** 5
- **When:** A non-agent runtime dependency probed via `Toolchain_install.ensure` (currently `cotype` per ADR-010, or `git` per ADR-013) is missing AND the user-scoped package manager either (a) requires `sudo` / manual install, (b) is itself not on `$PATH`, or (c) returned a non-zero exit. Distinct from `EAGENT_UNAVAILABLE` so the rendered remediation does not mislead with `ANTHROPIC_API_KEY` / backend-wiring guidance.
- **stderr:** `k4k: required tool "<binary>" not available: <reason>; try: <suggested-cmd>; install <binary> on $PATH and re-run (see kb/external/toolchain-install.md)`
- **Recovery:** Run the suggested install command (e.g. `pipx install cotype`) and re-launch k4k. The `suggested_command` is sourced from `Toolchain_install.suggest_for` and shown verbatim.

### EVERIFIER_UNAVAILABLE
- **Exit:** 2
- **When:** Verifier binary missing on `$PATH`, or first invocation fails before a result file is written.
- **stderr:** `k4k: verifier unavailable: <details>; check that the verifier executable from the .k4k spec's verifier_command is present and runnable`
- **Recovery:** Install the toolchain implied by the user's spec (the agent picks the toolchain per project; ADR-012). Common cases: `opam install dune`, `opam install rocq-prover`, etc.

### EVERIFIER_TOOL_ERROR
- **Exit:** 2
- **When:** Verifier returned `Tool_error`.
- **stderr:** `k4k: verifier error: <details>; see the per-run record in .k4k/version/<n>/agent-runs/ and .k4k/log.jsonl for context`
- **Recovery:** Inspect the per-version artefacts; fix the underlying tool issue.

### EDISK_FULL
- **Exit:** 4
- **When:** A write to `.k4k/` failed with `ENOSPC` (or equivalent). State is rolled back.
- **stderr:** `k4k: disk full while writing <path>; rolled back; free space and re-run`
- **Recovery:** Free space; re-run.

### ESTATE_CORRUPT
- **Exit:** 5
- **When:** `.k4k/manifest.json` exists but is unparseable or version-mismatched, OR a startup-phase `Unix.Unix_error` (mkdir/open) bubbles up (e.g. `EACCES` on the workdir, `EROFS` on `.k4k/`, `EPERM` on the PID file). `Watcher.startup`'s `typify_startup_exception` maps the bare exception into this variant with a typed message.
- **stderr:** `k4k: state corrupt: <details>; remove .k4k/manifest.json and re-launch k4k (the watcher rebuilds operational state from a clean start; user-owned content in the .k4k file is untouched)`
- **Recovery:** Above hint covers the common case (manifest mismatch). For permission/filesystem errors, the typed message names the failing syscall + path; fix at the filesystem level.

### EOWNERSHIP_VIOLATION
- **Exit:** 64
- **When:** A user-edit to a `## k4k:*` k4k-managed section conflicts with k4k's intended write and cotype declines to merge (returns `Conflict`). The watcher emits this rather than silently dropping the user's edit.
- **stderr:** `k4k: ownership violation: <details>; the user edited a k4k-managed section in a way the watcher cannot reconcile (cotype declined to merge); see .k4k/log.jsonl`
- **Recovery:** Resolve the diff3 markers cotype wrote into the file; re-run.

### EINVARIANT
- **Exit:** 64
- **When:** Fallthrough for an OCaml exception bubbling out of the watcher loop without a typed `K4k_error` wrap. Stack trace is written to `.k4k/log.jsonl`.
- **stderr:** `k4k: internal invariant violation: <details>; this is a bug in k4k — please report with .k4k/log.jsonl attached`
- **Recovery:** None at runtime; this is a code bug. Restart works if the underlying state is consistent.

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
