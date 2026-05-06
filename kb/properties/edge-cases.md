---
id: properties.edge-cases
type: spec
summary: Boundary conditions T1..TN k4k must handle correctly. Each entry has a triggering input, expected behavior, and observable artefact.
domain: properties
last-updated: 2026-05-02
depends-on: [glossary, properties.functional, properties.non-functional, spec.error-taxonomy]
refines: []
related: [conventions.testing-strategy]
---

# Edge Cases (T-series)

## One-liner

Every boundary condition that has a defined behavior. Each entry is a test target; absence of a T-entry for a boundary is itself a bug.

## Conventions

Each entry: **ID**, **Trigger**, **Expected behavior**, **Observable artefact**, **References** (P/NF/error IDs).

---

### T1 — Empty interaction file
- **Trigger:** `<file.k4k>` is zero bytes.
- **Expected:** Exit 1 with `EUNSTABLE`; no agent calls; no `.k4k/` mutation.
- **Observable:** stderr line `k4k: unstable: missing required sections: ...`; `.k4k/` either absent or unchanged.
- **Refs:** P2, EUNSTABLE. *Implementation note:* an empty file matches both `EFORMAT` (no frontmatter) and `EUNSTABLE` (no required sections). T1's intent is the latter — the structural-stability check fires first, before frontmatter strictness, so an empty file reports `EUNSTABLE`. The parser treats zero-byte input as a special case to preserve this ordering.

### T2 — Conflicting acceptance examples
- **Trigger:** Two `examples_accept` entries assert mutually contradictory outputs for the same `argv`/`stdin`.
- **Expected:** Stability fails at the formalization comparison step (the AST node containing the conflict cannot canonicalize).
- **Observable:** Clarification block appended naming the two examples by id and line.
- **Refs:** P2, P18.

### T3 — Pre-existing partial implementation
- **Trigger:** Working dir already contains source code that satisfies some properties of `D`.
- **Expected:** First verifier run identifies the established subset; gap = `D \ established`.
- **Observable:** `.k4k/gap/properties.json` contains only the unestablished subset; `current/spec.json` reflects the verifier evidence.
- **Refs:** spec.algorithms#gap-construction.

### T4 — User edits file mid-run
- **Trigger:** User modifies `<file.k4k>` between two gap-steps.
- **Expected:** Next step re-reads the file; if `user_sections_hash` changed, re-runs stability; otherwise proceeds.
- **Observable:** JSONL contains a `stability.start` event between the two gap-steps.
- **Refs:** P12, P13, Q15.

### T5 — Disk full during write
- **Trigger:** `ENOSPC` while writing to `.k4k/manifest.json.tmp`.
- **Expected:** Rollback (delete the tmp file), exit 4 with `EDISK_FULL`.
- **Observable:** No `.tmp` file remains; `manifest.json` is the prior version.
- **Refs:** NF3, EDISK_FULL.

### T6 — Non-UTF-8 interaction file
- **Trigger:** File contains a 0xFF byte outside any valid UTF-8 sequence.
- **Expected:** Exit 1 with `EENCODING`.
- **Observable:** stderr names the offending byte offset.
- **Refs:** EENCODING.

### T7 — Oversize interaction file
- **Trigger:** File ≥ 10 MB + 1 byte.
- **Expected:** Exit 1 with `EFILE_TOO_LARGE`. No parse attempted.
- **Observable:** stderr names the size.
- **Refs:** EFILE_TOO_LARGE.

### T8 — User edits a `## k4k:clarification:*` section before k4k's next save
- **Trigger:** User opens the interaction file in their editor mid-run, edits a `## k4k:clarification:<ts>` section (e.g. answering an appended clarification question by rewriting the block), and saves before k4k's next `cotype save`.
- **Expected (post-ADR-010):** k4k's next `cotype save --base-sha <captured>` returns `conflict` (exit 1 from cotype). k4k surfaces the conflict path to the user and exits 5 (`ESTATE_CORRUPT`-class). The file on disk has diff3 markers; the user resolves them in their editor and runs `cotype resolve <file>` before re-running k4k.
- **Observable:** JSONL `cotype.conflict` event with the file path and conflict id; cotype's forensic copy preserved under `.<basename>.cotype/conflicts/<id>/`.
- **Refs:** P12 (concurrency safety), ADR-010, `external/cotype.md`.
- **Pre-ADR-010 history:** This trigger previously caused a "hash mismatch → ownership flip → silent skip on next regen" flow. cotype's conflict outcome is louder and more honest about the situation.

### T9 — Both formalization runs invalid
- **Trigger:** Stub or genuinely degraded agent returns malformed JSON twice.
- **Expected:** Exit 1 with `EUNSTABLE`; clarification names the parse errors; no caching of bad output.
- **Observable:** Both raw responses persisted under `agent-runs/<id>/response.md` for audit; `desired/spec.json` not written.
- **Refs:** P18.

### T10 — Formalization runs disagree
- **Trigger:** Two successful formalization runs produce non-equivalent canonical hashes.
- **Expected:** Exit 1 with `EUNSTABLE`; clarification block naming the divergent AST nodes.
- **Observable:** A *divergence report* JSON file at `.k4k/agent-runs/<id>/divergence.json` listing the diff path.
- **Refs:** P18, ADR-005.

### T11 — Verifier returns Unknown for all properties
- **Trigger:** Verifier produces no `P<id>_*` test results (e.g. compile error in source).
- **Expected:** `S` set to all-unknown; gap = full `D`. Verifier output preserved in `verifier-runs/<id>/`.
- **Observable:** `result.json.by_property` maps every required id to `unknown`.
- **Refs:** spec.api-contracts#verifier.

### T12 — Property fails 3 times
- **Trigger:** A property is selected for 3 consecutive gap-steps; each agent patch rejected.
- **Expected:** Property marked `blocked`; clarification appended to interaction file; k4k continues with next-highest-risk non-blocked property.
- **Observable:** Property's `failure_count == 3, blocked == true`; clarification block in `<file.k4k>`.
- **Refs:** P6.

### T13 — Budget exhausted during formalization
- **Trigger:** First or second formalization call returns `Budget_exhausted`.
- **Expected:** Exit 4 with `EBUDGET`. No partial `desired/spec.json` written.
- **Observable:** `manifest.json.budget.used` reflects what was spent; no `desired.last_stable_at` update.
- **Refs:** P9, EBUDGET.

### T14 — Budget exhausted during gap-step
- **Trigger:** Cumulative `budget.used + this_call_budget > hard_per_invocation`.
- **Expected:** Skip this call; mark this gap-step as a failure (`failure_count` increment); exit 4 if no further work fits the budget.
- **Observable:** AgentRun `outcome == "budget-exhausted"`.
- **Refs:** P9.

### T15 — SIGINT during agent call
- **Trigger:** SIGINT delivered while waiting on the agent backend.
- **Expected:** Cancel the in-flight call (kill child process if subprocess; abort HTTP request if SDK); discard partial state; exit ≤ 5 s after signal.
- **Observable:** No `agent-runs/<id>/` directory left half-written; no manifest mutation since signal.
- **Refs:** NF1, P8.

### T16 — SIGINT during verifier call
- **Trigger:** SIGINT during a `dune build`/`dune test`.
- **Expected:** Terminate the verifier child; discard partial state; exit ≤ 5 s.
- **Observable:** Same as T15.
- **Refs:** NF1, P8.

### T17 — Stale `.k4k/` from older k4k version
- **Trigger:** `.k4k/manifest.json` exists but `k4k_version` is incompatible.
- **Expected:** Exit 5 with `ESTATE_CORRUPT`; recovery hint suggests `--reset`.
- **Observable:** stderr line names the version; no further work attempted.
- **Refs:** ESTATE_CORRUPT.

### T18 — User overrides a `k4k`-owned KB file
- **Trigger:** User edits `.k4k/spec/data-model.md` (k4k-generated). Hash mismatch detected on next run.
- **Expected:** Ownership treated as `user` for this and every subsequent run *as long as the hash mismatch persists*; KB-regen passes skip the file; manifest records the flip event.
- **Observable:** JSONL `ownership.flip` event with the file path. **k4k does NOT rewrite the file's frontmatter.** The `owner: k4k` tag remains; ownership is computed at read time by hash comparison every run. If the user later reverts their edits to match the recorded hash, the file is again k4k-owned (and eligible for regeneration). This preserves P1 — k4k never writes inside a region the user has authored.
- **Refs:** P1, P14, P16, ADR-006.

### T19 — Aspect maps to multiple properties
- **Trigger:** A single aspect entry in `D` (e.g. an `errors` entry) implies multiple invariants (raised when X, exits with code Y, messages match Z).
- **Expected:** k4k generates multiple `Property` entries with related `source.path`; each with independent `failure_count` and `risk_score`.
- **Observable:** `gap/properties.json` contains entries with the same `source.aspect` but different `source.path[]`.
- **Refs:** spec.algorithms#property-ids.

### T20 — Test name does not match convention
- **Trigger:** A test exists in the source tree but its name does not start with `P<id>_`.
- **Expected:** The verifier adapter ignores it for property mapping (it may still influence the global build pass/fail). k4k logs a `verifier.warning` and the auditor surfaces it.
- **Observable:** JSONL `verifier.warning` with the offending test name.
- **Refs:** spec.api-contracts#test-name-convention.

## Agent notes

> **Hidden boundaries are bugs.** If you discover a behavior the test suite did not exercise (e.g. "what if the verifier hangs?"), add a T-entry here *first* with the expected behavior, then write the test, then implement.

## Related files

- `properties/functional.md` — invariants these edge cases stress
- `properties/non-functional.md` — measurable criteria some edge cases reference
- `runbooks/audit-checklist.md` — Phase-5 verification of full T-coverage
