---
audit: summary-roll-up
timestamp: 2026-05-08T18:00:00Z
result: fail (3 critical, 8 high, 14 medium, 14 low; 1 critical and 1 high fixed in this pass)
---

# Audit Summary — 2026-05-08

Phase-5 quality audit on the v2 surface (commits up to and including
`5bcbeb3`). Seven axes dispatched in parallel via subagents per
`kb/runbooks/audit-checklist.md`. Each axis report lives at
`audit-2026-05-08-axis<N>-<name>.md`.

## Per-axis verdict

| Axis | Verdict | C | H | M | L |
|------|---------|---|---|---|---|
| 1 — Test gap | fail | 0 | 3 | 4 | 2 |
| 2 — Security | fail | 0 | 1 | 2 | 3 |
| 3 — Performance | pass (with deferred) | 0 | 0 | 2 | 1 |
| 4 — UX | fail | 0 | 1 | 2 | 3 |
| 5 — Spec compliance | fail | 3 | 3 | 3 | 3 |
| 6 — Simplicity | fail | 0 | 3 | 2 | 5 |
| 7 — Provability | fail | 0 | 0 | 1 | 0 |
| **Totals** | **fail** | **3** | **11** | **16** | **17** |

## Fixed in this pass (commit follows)

- **Axis 2 H1 (high)** — `Git.apply_diff` now rejects diffs touching
  `.k4k/`, `.git/`, absolute paths, or `..`-segments before any FS
  write. Extracted to `lib/diff_filter.{ml,mli}`. 5 new unit tests.
- **Axis 5 H3 (high)** — version-string mismatch: `lib/manifest.ml`
  was `0.1.0`, `bin/main.ml` was `0.2.0`, `lib/version_persist.ml`
  duplicated `0.1.0`. Single source of truth now in
  `Manifest.k4k_version_string` (= `"0.2.0"`); `bin/main.ml` and
  `Version_persist.write_manifest` both reference it.
- **Axis 6 low (file cap)** — `lib/watcher_loop.ml` was 201 lines;
  now exactly 200 by inlining one let.
- **Axis 7 medium (KB cross-refs)** — 5 dangling `related:` /
  `depends-on:` ids fixed: `architecture.decisions` →
  `architecture.decisions.index` (overview + context-economy);
  `external.dune` removed from adr-004; `external.claude-code`
  removed from adr-003 + context-economy.

## Fixes deferred to follow-up commits

The remaining findings sort cleanly into four follow-up commits. No
single one is large; together they would close the audit.

### Commit A — Spec compliance (Axis 5 C1, C2, C3, M1, M2)

- **C1**: `kb/spec/algorithms.md`'s top-level loop is pre-ADR-011.
  Update to describe the v2 polling watcher and the
  ADR-013 version-as-git-branch lifecycle.
- **C2**, **C3**: data-model.md and error-taxonomy.md drift.
- **M1**: disambiguate `Property.blocked` vs `tradeoff` semantics in
  the spec.
- **M2**: drop dune-ocaml references from `kb/spec/api-contracts.md`
  (the example was deleted in `cd0b019`).

These are KB edits, not code changes (per CLAUDE.md "if the code
contradicts the KB, the KB wins by default — but here ADRs 011/012/013
are the actual normative source post-v2-reorientation").

### Commit B — Orphan-module deletion (Axis 6 H1, H2, H3)

The v2 watcher rewrite (`bin/main.ml` → `Watcher.run` →
`Watcher_loop`/`Watcher_dev`/`Version_loop`/`Gap_step`) bypasses the
v0 `Run_loop` chain entirely. These modules are now orphans:

- `lib/run_loop.{ml,mli}` (~200 lines) — replaced by
  `Watcher_loop`/`Version_loop`.
- `lib/harness.{ml,mli}` — replaced by `Watcher.run` startup +
  `Version_loop.run`.
- `lib/full_check.{ml,mli}` — replaced by inline checks in the v2
  formalize → version-loop pipeline.
- `lib/backend_external.{ml,mli}` — never wired into the v2
  watcher; the example backend at `examples/backends/claude-code/`
  is the production path. Either wire `Backend_external` into
  `Watcher_dev.resolve_invoke` (matching the documented surface in
  `kb/external/backend-protocol.md`) OR delete it.
- `lib/backend_stub.{ml,mli}` and `lib/verifier_stub.{ml,mli}` —
  test-only; replaced by `Backend_canned` + the synthetic verifier
  shell script. Delete.

Plus: update `kb/architecture/overview.md` to describe the v2
module graph (currently lists `Run_loop` and friends as the
production path).

### Commit C — Test gap (Axis 1 H1, H2, H3, M1)

- **H1**: add P12, P21, P23 prefixed tests (currently missing).
- **H2**: add T2, T15, T19 prefixed tests.
- **H3**: `Watcher_pid` (single-instance enforcement, ADR-011) is
  completely untested. Add lifecycle tests: acquire on a fresh
  `.k4k/`, refuse to acquire when a PID is already alive,
  release-on-exit, stale-PID cleanup.
- **M1**: wire `bisect_ppx` into `lib/dune` + `k4k.opam` so check 5
  (≥80% coverage) becomes measurable.

### Commit D — UX (Axis 4 H1, M1, M2)

- **H1**: closed error catalog has unreachable IDs
  (`EOWNERSHIP_VIOLATION`, `EINVARIANT`); bare `Unix_error`s leak
  bypassing the catalog (e.g. `k4k /nonexistent/path`); `--help`
  shows cmdliner exit codes 123/124/125 instead of the taxonomy's.
  Wrap startup in a try/with that maps `Unix_error` → typed
  `K4k_error`; suppress cmdliner's exit-code defaults.
- **M1**: `-vv` is a no-op over `-v`. `lib/watcher.ml:94-99` — both
  branches write the same line. Either implement debug-level subprocess
  argv logging or drop `-vv`.
- **M2**: `E_state_corrupt` suggests `--reset` and `E_max_steps`
  suggests `--max-steps`, neither of which exists in v2. Strip the
  phantom remediations or implement them.

## Single most load-bearing finding (already fixed)

**Axis 2 H1** — `Git.apply_diff` had no path filter on agent-supplied
diffs. v2's direct-commit gap-step (ADR-013 §2 step 3) deliberately
removed the scratch-branch isolation v1 used. `git reset --hard HEAD`
on rejection does NOT clean `.k4k/` (it's in `is_ignorable_path`), so
a single poisoned diff could permanently invalidate
`manifest.json` / `version/<n>/audit.md`, bypassing the
determinism contract. Fixed in this pass: `lib/diff_filter.{ml,mli}`
+ filter call in `Git.apply_diff`. The test suite gained 5 unit tests
(suite `Git`).

## Single most load-bearing finding NOT YET fixed

**Axis 5 C1** — `kb/spec/algorithms.md`'s top-level loop describes
the pre-ADR-011 binary (`exit 1` on instability,
`--max-steps`/`--budget`/`--reset` flags, synchronous loop). A
contributor following the spec to extend the watcher would break the
v2 autonomous-watcher contract. The fix is a KB rewrite (Commit A).

## Pattern observed across axes

The dominant failure mode is **spec lag, not code drift**. The v2
reorientation shipped via ADRs 011/012/013, the implementation
tracked them, and the test suite tracked the implementation. Several
KB files under `kb/spec/`, `kb/architecture/overview.md`, and
`kb/runbooks/audit-checklist.md` got partial updates only. Per
CLAUDE.md, KB normally wins by default — but post-v2 the ADRs are
the actual normative source. Three KB files (`spec/algorithms.md`,
`architecture/overview.md`, `runbooks/audit-checklist.md`) need
explicit alignment passes (the audit-checklist itself references
removed flags like `--check`).

## Total work remaining to pass

- Commit A (spec docs): ~3-4 KB rewrites, no code.
- Commit B (orphan modules): ~600 LOC delete + overview rewrite.
- Commit C (tests): 6-9 new tests + bisect wiring.
- Commit D (UX): ~50 LOC code + test cases.

The audit's "iterate until 0 criticals" rule (Ralph Loop, max 5)
applies. Three criticals all resolve with Commit A.
