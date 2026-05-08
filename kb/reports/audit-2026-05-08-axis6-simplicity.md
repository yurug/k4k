---
audit: axis6-simplicity
timestamp: 2026-05-08T00:00:00Z
result: fail
---

# Findings — Axis 6 (Simplicity)

Per `kb/runbooks/audit-checklist.md#axis-6--simplicity`, six checks were
run against `lib/**/*.{ml,mli}`, `kb/architecture/overview.md`, and
recent git history. Result: **fail** (two highs, one medium, several
lows). The dominant theme: v2 batches 4–5 introduced `Watcher_*`,
`Version_*`, `Tradeoff_flow`, `Inline_blocks*` etc. but the previous
v0/v1 production chain (`Harness` → `Run_loop` → `Full_check`) was
left in the tree as test-only code and the architecture overview was
not updated.

## Score per check

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | File length ≤ 200 lines | fail (low) | One offender: `lib/watcher_loop.ml` is **201** lines (`wc -l`). All other 64 `.ml` files ≤ 200. Six files within 5 lines of the cap (run_loop 200, version_loop 197, gap_step 196, persist 195, backend_external 194, verifier_external 191). |
| 2 | Function length ≤ 30 lines | fail (medium) | At least four functions exceed the 30-line cap: `lib/watcher_form.ml:78` `run` ≈ 51 lines; `lib/run_loop.ml:118` `loop_iter` ≈ 41 lines (in dead code, see check 5); `lib/watcher_dev.ml:105` `try_run_version` ≈ 37 lines; `lib/inline_blocks_sections.ml:56` `find_tradeoff_block` ≈ 32 lines and `:91` `find_clarification_block` ≈ 31 lines (these two are near-duplicate logic, see Medium below). Counted by `awk` over `^let `/`^and ` boundaries; spot-checked. |
| 3 | Cyclomatic complexity ≤ 10 | pass (with caveat) | No automated tool wired (no `merlin` complexity check in tree). Visual inspection of the longest/branchiest functions: `try_run_version` has ~9 decision points (one outer `match`, one nested `match`, one `try` with two handlers); `version_loop.drive_property_full` ~8; `watcher_loop.one_tick` ~7. None exceed 10 by inspection. Caveat: this is a manual sample, not automated coverage. |
| 4 | No dead code / `dune build @check` clean with `-w +unused` | pass | `dune clean && dune build` (with `lib/dune` flags `-w +a-4-40-41-42-44-45-48-58-59-60-66-67-68-69-70 -strict-sequence`) returns RC=0 with zero warnings. |
| 5 | Every module documented in `architecture/overview.md` invoked from ≥ 2 call sites | **fail (high)** | Four documented modules have **zero production call sites** — only test references: `Run_loop`, `Backend_external`, `Backend_stub`, `Verifier_stub`. See Critical/High below. Additionally, the overview itself is severely out of date — see Medium. |
| 6 | No comment-only commits in recent history | pass | `git log --shortstat -30` shows every commit modifies code or KB content; the smallest is `93ac4c7` (4 files, 43 ins/9 del); no commit is purely cosmetic/comment churn. |

## Critical
_(none — the dead-code modules are isolated, not actively misleading
behaviour, but see High.)_

## High

- **H-1: `Run_loop` is the documented top-level production driver but has
  zero production callsites.** `lib/run_loop.ml` (200 lines) and
  `lib/run_loop.mli` are referenced only from `test/unit/test_unit.ml`
  (10 sites). `bin/main.ml` calls `Watcher.run`, which threads through
  `Watcher_loop` → `Watcher_dev` → `Version_loop` → `Gap_step` —
  `Run_loop` is bypassed entirely.
  - evidence: `grep -rEn "Run_loop\." lib/ bin/` returns only one
    `lib/run_loop.ml:3` doc-comment self-reference;
    `test/unit/test_unit.ml` has 10 callers.
  - cost: the file declares its own `loop_iter` (41-line, also a
    check-2 violator) and duplicates per-step orchestration that now
    lives in `Version_loop`/`Watcher_loop`. Future readers see two
    "the loop" modules and don't know which is current.
  - fix: delete `lib/run_loop.ml`, `lib/run_loop.mli`, and the
    corresponding alcotest cases in `test/unit/test_unit.ml`
    (lines ~2990–4290, the `Run_loop.run`-only suites). Update
    `kb/architecture/overview.md` to drop the `run_loop` row from the
    module table and the `# Modules` listing. Estimated removal: ~200
    LOC of `lib/`, ~300 LOC of test scaffolding, plus one KB section.

- **H-2: `Harness` / `Full_check` chain is also test-only.**
  `lib/harness.ml` (62 lines) declares `module type S` and
  `Harness.Make`; `lib/full_check.ml` (148 lines) wraps it. Both are
  called only from `test/unit/test_unit.ml:585` (`module H = Harness.Make ...`)
  and `lib/run_loop.ml:3` (a doc comment). The architecture overview
  describes `Harness` as the DI surface that `bin/main.ml` constructs,
  but `bin/main.ml` no longer uses it (post-ADR-011 watcher daemon).
  - evidence: `grep -rEn "Harness\." lib/ bin/` → one production hit
    in `lib/full_check.ml` (which is itself orphan production-side);
    `grep -rEn "Full_check\." lib/ bin/` → only a comment reference.
  - cost: ~210 LOC of orphan production code + the test cases that
    pin them. The DI seam they document is duplicated by the
    `agent_invoke` / `verifier_run` closures in
    `Version_loop.config` and `Watcher_dev.resolve_invoke`, which is
    *another* DI layer with subtly different naming.
  - fix: option (a) delete `lib/harness.ml{,i}`, `lib/full_check.ml{,i}`,
    and their tests; option (b) re-route `bin/main.ml` through
    `Harness.Make` if the DI surface is intended to come back.
    Pick one; the current half-state is the worst of both worlds.
    Update `kb/architecture/overview.md` either way.

- **H-3: `Backend_external` and the two stubs (`Backend_stub`,
  `Verifier_stub`) are documented as the production agent/verifier
  adapters but have zero production callsites.** `bin/main.ml` →
  `Watcher.run` → `Watcher_dev.resolve_invoke` builds the agent
  invoke from `Backend_canned` (test) or returns a `Tool_error`
  closure when no `K4K_STUB_RESPONSES` is set; **there is no
  production wiring of `Backend_external`**.
  - evidence:
    - `grep -rEn "Backend_external\.[a-z]" lib/ bin/` (excluding
      `Backend_external_parse`) returns zero hits; only
      `test/unit/test_unit.ml` (~30 sites) instantiates it.
    - `lib/watcher_dev.ml:19-33` `resolve_invoke` only knows about
      `Backend_canned` and a no-op fallback.
    - `lib/agent_backend.ml:4` doc-comment still says
      "[Backend_external] is the production implementation".
  - cost: production agent calls fall back to `Tool_error
    "no K4K_STUB_RESPONSES configured"`. The watcher emits
    `agent.no_canned` and is otherwise inert. Either the production
    path is incomplete (release-blocker) or `Backend_external`'s 194
    LOC + `.mli` + ~40 test cases are dead weight. Same logic for the
    `Verifier_stub` (`Verifier_external` IS used at
    `lib/watcher_dev.ml:39`, so only the stub is the orphan there).
  - fix: wire `Backend_external` into `Watcher_dev.resolve_invoke`
    (the natural place: when `K4K_STUB_RESPONSES` is unset, fall
    through to the configured external backend per
    `kb/external/backend-protocol.md`); OR delete
    `lib/backend_external.ml{,i}` if v2 has decided cotype-side
    backends are the only way. The decision should be ratified by an
    ADR amendment.

## Medium

- **M-1: `kb/architecture/overview.md` is severely out of date.** 28
  modules in `lib/` are not mentioned in the overview's module table
  at all: every `Watcher_*` (5 modules: `watcher`, `watcher_dev`,
  `watcher_form`, `watcher_loop`, `watcher_pid`, `watcher_prune`),
  `Version_tradeoff`, `Version_user_edits`, `Tradeoff_flow`,
  `Inline_blocks` + `Inline_blocks_sections`, `Status_splice`,
  `Tty_status` (it's mentioned as a Logger sub-module but is now its
  own file), `Toolchain_install`, `Starter_template`, `Audit_md`,
  `Clarification`, `Cotype_parse`, `Cotype_stub`, all `Parser_*` and
  `Backend_external_parse`, `Verifier_external_parse`,
  `Characterization_decoder`, `Characterization_json`, `Property_id`,
  `Property_json`. Conversely the overview still lists the retired
  `Convergence` (deleted in `a9b2ede`) as a module.
  - evidence:
    `comm -23 <(ls lib/*.ml | xargs -n1 basename | sed 's/\.ml$//' | sort) <(grep -oE '\| \`[a-z_]+\`' kb/architecture/overview.md | tr -d '|`' | tr -d ' ' | sort -u)`
    yields the 28 modules; reverse comparison includes `convergence`.
  - cost: this directly defeats Check 5 (the thing this audit is
    measuring against). It also misleads new contributors about the
    DI seam (overview shows `Harness` as central; reality is
    `Watcher_loop`).
  - fix: rewrite the "Top-level module graph" diagram and the module
    table to reflect the v2 watcher daemon (ADR-011/013). Pair this
    with the H-1/H-2/H-3 cleanup so the doc rewrite isn't churn.

- **M-2: `find_tradeoff_block` and `find_clarification_block` in
  `lib/inline_blocks_sections.ml` are near-duplicates.** Lines 56–87
  and 91–121 share the same skeleton (32+31 lines each, both at the
  function-length cap). The only differences are the prefix string
  and the return shape (3-tuple vs 4-tuple).
  - evidence: `lib/inline_blocks_sections.ml:56` and `:91`; visual
    diff shows ~25 of 32 lines identical.
  - fix: extract a private helper
    `find_h2_block ~prefix raw : (ts * body_start * stop * i) option`
    that does the byte-scan; keep the two public functions as
    one-line wrappers that re-shape the tuple. Drops both functions
    below the 30-line cap and removes the duplication.

## Low

- **L-1: `lib/watcher_loop.ml` is one line over the 200-line cap (201
  lines).** `wc -l` confirms; the file ends at line 201. Trivial
  one-line trim possible (collapse the trailing blank after the
  `loop ()` call) or factor `on_rollback` (lines 107–124, 17 lines)
  into `Watcher_dev` where related branch lifecycle lives.
  - evidence: `wc -l lib/watcher_loop.ml` → `201`.
  - fix: move `on_rollback` to `Watcher_dev` (semantic peer of
    `try_run_version`); `Watcher_loop` drops to ~184 lines.

- **L-2: `watcher_form.run` is 51 lines (cap 30).** Mixed
  responsibilities: caches lookup, prompt rendering, two-run
  formalization, three-way result match, persistence, two emit
  branches.
  - evidence: `lib/watcher_form.ml:78–128`.
  - fix: extract three small helpers (`cached_outcome`,
    `handle_stable`, `handle_unstable`); the top-level `run` becomes
    a 12-line dispatch. (Same shape as the cleanup in
    `Watcher_loop.one_tick`, which was already refactored this way.)

- **L-3: `try_run_version` is 37 lines.** Same recipe as L-2;
  extract the inner `Ok d` branch into a helper
  `start_or_skip ~d ~prev` returning the same outcome variant.
  Drops to ~18 lines.
  - evidence: `lib/watcher_dev.ml:105–141`.

- **L-4: `run_loop.loop_iter` is 41 lines.** Dead code (see H-1) so
  the practical fix is deletion, but if `Run_loop` is kept the
  function should be split: the four `Continue/Blocked/Budget` arms
  are independent and can each be a one-liner helper.
  - evidence: `lib/run_loop.ml:118–158`.

- **L-5: Six files within 5 lines of the 200-line cap.** Any new
  feature on these touches the cap immediately:
  `run_loop.ml` 200, `version_loop.ml` 197, `gap_step.ml` 196,
  `persist.ml` 195, `backend_external.ml` 194,
  `verifier_external.ml` 191. No fix required now, but flagged for
  the next refactor pass — the convention is "a hard limit", not a
  ceiling to dance against.
  - evidence: `wc -l lib/*.ml | sort -rn | head`.

## Notes

The single most actionable simplicity win is **H-1** (delete
`Run_loop`): one module with no production callers, ~200 LOC of `lib/`
+ ~300 LOC of test code disappears, the architecture overview shrinks
by one row, and check 2 (`loop_iter` 41-liner) gets resolved as a
side-effect. H-2 is the next domino. Both belong to the same v2
migration that retired `Convergence` (`a9b2ede`); finishing that
cleanup is the right next step.

Check 3 (cyclomatic complexity) was sampled visually because no tool
is wired. Wiring `merlin --print-syntax-stats` or a dedicated
complexity linter into CI would let the next audit be automated; the
current sample-and-pass is fragile.

## Related files

- `lib/run_loop.ml{,i}`, `lib/harness.ml{,i}`, `lib/full_check.ml{,i}`,
  `lib/backend_external.ml{,i}`, `lib/backend_stub.ml{,i}`,
  `lib/verifier_stub.ml{,i}` — H-1, H-2, H-3 candidates.
- `lib/watcher_loop.ml` — L-1.
- `lib/watcher_form.ml`, `lib/watcher_dev.ml` — L-2, L-3.
- `lib/inline_blocks_sections.ml` — M-2.
- `kb/architecture/overview.md` — M-1.
- `kb/conventions/code-style.md` — the file/function/cyclomatic caps
  this axis enforces.
