---
audit: axis7-provability
timestamp: 2026-05-08T00:00:00Z
result: fail
---

# Findings — Axis 7 (Provability)

Per `kb/runbooks/audit-checklist.md#axis-7--provability`, six checks
were run against `lib/**/*.{ml,mli}`, `kb/properties/functional.md`,
and `kb/**/*.md`. Result: **fail** (one medium check; one deferred).

## Score per check

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | `@invariant P<n>` annotations all map to a real `P*`/`NF*` entry | pass | 78 `@invariant` occurrences across `lib/`; unique IDs `P1..P23` + `NF4,NF5,NF7,NF8`; all present in `kb/properties/functional.md` and `kb/properties/non-functional.md`. |
| 2 | Every `P*` entry has ≥1 `@invariant` callsite | pass | `comm -23` of canonical `P1..P23` against IDs grepped from `lib/` is empty (all 23 covered). |
| 3 | KB cross-refs resolve | fail (medium) | 5 dangling front-matter refs (see Medium below); 0 broken inline links among KB-internal docs (after excluding the two external survey docs `claude-code-report.md`, `opencode.md` whose links point into other repos by design). |
| 4 | No "agent-validates" patterns in source | pass | `grep -rE "agent.*ok\|agent.*pass\|model.*confirm" lib/` yields hits only on the function name `agent_invoke` (regex `agent.*ok` matches `agent_inv*ok*e` because `invoke` contains the substring `ok`); no semantic agent-self-validation. Manual scan for `(if\|when\|match) ... agent ... (says\|claims\|reports) ... (ok\|pass\|valid\|done)` returns empty. |
| 5 | State transitions are deterministic predicates over `(D, S, verifier, user input)` | pass | `lib/gap_step.ml:53-58` (`regressed`), `:131-145` (`on_verifier_ok`), `:78-88` (`bump_and_classify`), `:179-196` (`step`) decide outcomes purely from `Verifier.result_ok`, `prev_status`, `failure_count`, and `budget_remaining`. `lib/version_loop.ml:81-101` is plain case-analysis on the tagged outcome from `Version_tradeoff.drive_at_tier`. No agent-text inspection in any conditional. |
| 6 | KB-quiz roundN | n/a — deferred | Per the task brief, this requires a fresh subagent with KB-only access. Flagged for a separate audit run; **not blocking** Axis 7 closure beyond this caveat. |

## Critical
_(none)_

## High
_(none)_

## Medium

- **CR-1: Five dangling front-matter cross-refs in `kb/`.** The `related:` / `depends-on:` lists below name IDs that no document declares.
  - evidence:
    - `kb/architecture/overview.md` → `related: architecture.decisions` — no doc declares `id: architecture.decisions`; the actual index id is `architecture.decisions.index` (`kb/architecture/decisions/INDEX.md`).
    - `kb/architecture/decisions/adr-004-verifier-extension.md` → `related: external.dune` — no `kb/external/dune.md` exists; closest siblings are `external.ollama`, `external.cotype`, `external.toolchain-install`.
    - `kb/architecture/decisions/adr-003-pluggable-backend.md` → `related: external.claude-code` — no `kb/external/claude-code.md`; the survey doc lives at `kb/claude-code-report.md` and has no front-matter `id:`.
    - `kb/conventions/context-economy.md` → `related: external.claude-code` (same as above).
    - `kb/conventions/context-economy.md` → `depends-on: architecture.decisions` (same as overview).
  - fix:
    1. Replace `architecture.decisions` with `architecture.decisions.index` in `kb/architecture/overview.md` and `kb/conventions/context-economy.md`.
    2. Either add a stub `kb/external/dune.md` with `id: external.dune` (only if dune deserves an external-system note) or remove that ref from `adr-004` and inline the citation.
    3. Either give `kb/claude-code-report.md` a front-matter block with `id: external.claude-code` (it has none today) or replace the two `external.claude-code` refs with the actual filename relative-link (the doc already exists; only the ID is missing). Recommended: add the front-matter id — keeps `related:` fields working as graph edges.

## Low
_(none)_

## Notes

- **Coverage of P20.** `P20` (every public function carries an `@invariant`)
  declares the property but is not itself enforced by a CI lint. The
  audit found `P20` is referenced by `lib/logger.mli:68`, but no
  pre-commit / dune check fails when a new public function lands without
  an `@invariant`. That's an Axis-1 / Axis-6 concern, not Axis 7 — flagging
  for cross-axis tracking only.
- **Check 4 regex false-positive.** The audit regex
  `grep -E "agent.*ok|agent.*pass|model.*confirm"` matches the function
  name `agent_invoke` because `invoke` contains the substring `ok`. The
  hits are not semantic. Future audits should tighten the regex to e.g.
  `\bagent\b[^_]*\b(ok|pass|done|valid|confirm)\b` or scope to comments
  and conditionals only.
- **State-transition determinism is the strongest provability evidence
  in the codebase.** `lib/gap_step.ml`'s `step` and `on_verifier_ok`
  read like a literal transcription of `kb/spec/algorithms.md#gap-step`
  (lines 142-160), with `regressed` providing the P5 predicate and
  `bump_and_classify` providing the P6 three-strikes predicate. The
  agent's text never enters a control-flow decision: the only path
  out of `agent_invoke` is `extract_diff` → `Git.apply_diff` →
  `Verifier.run` → `by_property` lookup, which is verifier-evidence
  all the way down.
- **Most-actionable provability gap:** CR-1's `architecture.decisions`
  refs (the most-cited orphan, 2 sites). Fixing those two is a
  ~2-minute Edit. The other three orphans need a one-line decision
  ("add stub doc" vs "drop ref") before fixing.

## Related files

- `kb/properties/functional.md` — canonical P1..P23 list
- `kb/properties/non-functional.md` — canonical NF1..NF8 list
- `kb/spec/algorithms.md#gap-step` — the deterministic predicate the source mirrors
- `lib/gap_step.ml`, `lib/version_loop.ml`, `lib/tradeoff_flow.ml` — state-machine call sites scanned for check 5
