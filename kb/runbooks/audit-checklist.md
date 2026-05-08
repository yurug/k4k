---
id: runbooks.audit-checklist
type: procedure
summary: The Phase-5 quality audit checklist — seven axes (test gap, security, performance, UX, spec compliance, simplicity, provability) each with concrete checks and pass criteria.
domain: runbooks
last-updated: 2026-05-02
depends-on: [glossary, properties.functional, properties.non-functional, properties.edge-cases]
refines: []
related: [conventions.testing-strategy, spec.error-taxonomy]
---

# Audit Checklist

## How to use this checklist

For each axis, spawn one fresh subagent with KB-only access plus the source tree. The subagent answers each check with `pass | fail | n/a`, cites evidence (file:line for fails), and writes findings to `kb/reports/audit-<timestamp>-<axis>.md`. Findings classified `critical` block release; `high` must be fixed or documented with a rationale; `medium`/`low` are tracked.

Iterate until 0 criticals (Ralph Loop, max 5).

---

## Axis 1 — Test gap analysis

### Checks
1. Every entry in `properties/functional.md` (`P*`) has ≥ 1 test whose name starts with that ID.
2. Every entry in `properties/non-functional.md` (`NF*`) has ≥ 1 test or measurement procedure documented.
3. Every entry in `properties/edge-cases.md` (`T*`) has ≥ 1 test whose name starts with `T<id>_`.
4. Every public function in `lib/` has ≥ 3 tests.
5. Code coverage measured by `bisect_ppx` ≥ 80%.
6. No test is `xfail`/`skip` without a TODO referencing a tracked issue.

### Pass criterion
All six checks pass; coverage report attached to the audit findings file.

---

## Axis 2 — Security

### Checks
1. **Secrets quarantine (`NF5`)**: poison-canary `ANTHROPIC_API_KEY=POISON-CANARY` test triggers every error path; no occurrence of `POISON-CANARY` in any output stream or log file.
2. **Subprocess invocation**: every external invocation uses `Unix.execvp` or higher-level wrapper; no `Sys.command`. Audit by `grep -r 'Sys.command' lib/` — must return empty.
3. **State-confinement (`NF4`)**: full `strace` of an integration scenario; assert no writes to `/tmp`, `$HOME`, or any path outside `<file.k4k>`, `.k4k/`, and the source tree.
4. **No untrusted code execution paths**: the agent is allowed to write into the in-flight `k4k/version/<n>` branch tree (ADR-013 §2 step 3, v2 direct-commit), never into `.k4k/` or other repos.
5. **Logs do not leak environment**: `grep -i "ANTHROPIC\|API_KEY\|TOKEN\|SECRET" .k4k/log.jsonl` returns empty after a clean run.
6. **`.k4k/` permissions**: created with `0o755` for dirs, `0o644` for files; no `0o777`.

### Pass criterion
All six checks pass with attached evidence.

---

## Axis 3 — Performance

### Checks
1. **Memory ceiling (`NF2`)**: 50-step integration scenario; max RSS < 512 MB.
2. **Wall-clock per gap-step (median)**: < 60 s under stub backends.
3. **API request budget**: cumulative `budget_used` (per `external/backend-protocol.md`) per realistic scenario fits inside the soft caps in `domain/prd.md#non-functional-expectations` and the per-call max in `conventions/context-economy.md` (R1).
4. **Atomic writes (`P10`)**: 100 random-kill iterations; manifest parses every time.
5. **Lock-free reads**: post-ADR-010 k4k itself does not call `flock`; cotype's sidecar lock is held only by cotype's mutating commands. Verify by `grep -r 'Unix.lockf\|flock' lib/` returning empty.
6. **No N+1 agent calls**: KB regeneration touches *only* affected files (`P16`); audit by counting agent calls per gap-step.

### Pass criterion
All six checks pass; numerical results in the findings file.

---

## Axis 4 — UX

### Checks
1. **stdout/stderr discipline (`P11`)**: piped run separates streams cleanly.
2. **Exit codes**: every error from `spec/error-taxonomy.md` is reachable in tests; observed exit code matches the table.
3. **TTY status updates correctly**: `script -c "k4k ..."` produces a single in-place line; `tee` produces one log line per transition.
4. **`--check` is silent on success**: `k4k --check stable.k4k` prints `stable\n` and nothing else.
5. **Error messages cite remediation**: every `k4k:` error line contains either a path, a section id, or a `recovery hint`.
6. **`-v` / `-vv` are additive**: `-vv` includes everything `-v` shows, plus more.

### Pass criterion
All six checks pass.

---

## Axis 5 — Spec compliance

### Checks
1. **Every algorithm step in `spec/algorithms.md` is implemented exactly once.** Audit via grep for the section anchors (e.g. `algorithms.md#canonicalize`) referenced in source comments.
2. **`spec/data-model.md` schemas match runtime** — JSON-schema test on every persisted file shape.
3. **Closed error taxonomy (`P7`)**: `grep -E "K4k_error|raise.*Error" lib/` lists every emit site; cross-check against `spec/error-taxonomy.md`. Mismatch ⇒ critical.
4. **Section IDs in `spec/config-and-formats.md` match the parser** — auto-test by feeding a canonical `<file.k4k>`.
5. **`api-contracts.md` signatures match `.mli`** — diff signatures.
6. **No undocumented CLI flag** — `--help` output checked against `domain/prd.md#command-surface`.

### Pass criterion
All six checks pass.

---

## Axis 6 — Simplicity

### Checks
1. **File length** ≤ 200 lines (`grep -c $ lib/*.ml | awk '$2 > 200'` empty).
2. **Function length** ≤ 30 lines (lint check).
3. **Cyclomatic complexity** ≤ 10 (`merlin` or equivalent).
4. **No dead code** — `dune build @check` with `-w +unused`; warnings = errors.
5. **No premature abstraction**: every module documented in `architecture/overview.md` is invoked from at least 2 call sites; orphans are critical.
6. **No comment-only commits** in the recent history that do not also change code or KB.

### Pass criterion
All six checks pass.

---

## Axis 7 — Provability

### Checks
1. **Every `@invariant P<n>` annotation in source maps to an existing entry in `properties/functional.md`** — automated by grepping `@invariant` and checking IDs.
2. **Every `P*` entry in `properties/functional.md` is referenced by ≥ 1 source location's `@invariant`.**
3. **Each KB cross-reference resolves** — every `related:` ID and inline link refers to a real file.
4. **No "the agent will validate ..." patterns** in source — `grep -E "agent.*ok|agent.*pass|model.*confirm" lib/` returns empty.
5. **Every state transition is justified** by a deterministic predicate over `(D, S, verifier output, user input)` per `algorithms.md`. Reviewer-confirmed.
6. **The KB-quiz** (`reports/kb-quiz-roundN.md`) — 10 hard questions about the system, answered by a fresh subagent with KB-only access; full marks expected.

### Pass criterion
All six checks pass.

---

## Findings file format

Each axis's subagent writes:

```
---
audit: <axis>
timestamp: <iso8601>
result: pass | fail
---

# Findings — <axis>

## Critical
- <id>: <one-line description>
  - evidence: <file:line> or attached log
  - fix: <suggested>

## High
...

## Medium
...

## Low
...

## Notes
<any context the auditor wants future audits to inherit>
```

## Agent notes

> **No partial passes.** The audit is binary per axis. A "mostly passing" audit hides bugs the next user will hit.
>
> **Iterate.** If 2 audits in a row find the same critical, the underlying issue is bigger than the immediate fix — go back to Phase 3 and re-plan that slice.

## Related files

- `properties/functional.md`, `properties/non-functional.md`, `properties/edge-cases.md` — what the audit checks
- `conventions/testing-strategy.md` — what tests are expected to exist
- `conventions/error-handling.md` — what closed-set discipline looks like in code
