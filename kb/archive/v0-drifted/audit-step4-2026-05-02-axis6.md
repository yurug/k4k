---
audit: axis-6-simplicity
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 6 (Simplicity)

## Method

1. File length: `wc -l lib/*.ml lib/*.mli` — every file ≤ 200 lines.
   Largest are `gap_step.ml` (183), `stability.ml` (174),
   `persist.ml` (170).
2. Function length: manual review of every public function. The
   discipline is preserved by splitting into helper functions (e.g.
   `loop_iter`, `regen_set`, `restability_check`) — none exceed
   30 lines.
3. Cyclomatic complexity: manual review. The branching density is
   low; pattern-match heads typically have ≤ 6 arms.
4. Dead code: `dune build @check` is clean with strict warnings.
   The lint test `tests_per_file_minimum` (≥ 30 cases) is satisfied
   (149+ unit cases).
5. No premature abstraction: every module in `architecture/overview.md`
   has at least one caller. Stubs (`Backend_stub`, `Verifier_stub`)
   ship in `lib/` because the PRD's `--backend=stub` flag uses them
   in production.
6. No comment-only commits: git log review across step 1–4 shows
   every commit either changes code or introduces a tracked KB
   addition (audit reports, prompts, etc).

## Critical
(none)

## High
(none)

## Medium
- `gap_step.ml` is at 183 lines — within the cap but close. If a
  future feature pushes it over, the `try_apply_and_verify` /
  `dispatch_response` helpers are natural split points.
- `stability.ml` is at 174 lines — same comment.

## Low
- The `Re` regex compositions in `logger.ml` could be further
  factored. Current style favors readability.

## Notes

File-size summary (top 10):

| File                                      | Lines |
|-------------------------------------------|-------|
| `lib/gap_step.ml`                         | 183   |
| `lib/stability.ml`                        | 174   |
| `lib/persist.ml`                          | 170   |
| `lib/verifier_dune_ocaml.ml`              | 166   |
| `lib/backend_claude.ml`                   | 163   |
| `lib/run_loop.ml`                         | 160   |
| `lib/characterization_decoder.ml`         | 149   |
| `lib/canonicalize.ml`                     | 145   |
| `lib/kb_regen.ml`                         | 143   |
| `lib/parser_sections.ml`                  | 130   |

All ≤ 200. All `.mli` files have matching `.ml` files. The
`code_style_no_Sys_command`, `P7_unknown_error_is_invariant_violation`,
`tests_per_file_minimum`, `P20_invariant_coverage_at_least_80_percent`
lint tests collectively enforce structural simplicity.
