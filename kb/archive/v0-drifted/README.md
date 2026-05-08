# v0-drifted — historical record

These files are kept verbatim from the v0 build (Phases 1–7 + the ADR-008/009/010 retrofits + the Phase-5 audit cycles). They are accurate snapshots of what was built and the rationale at the time, but they were authored under a **drifted UX framing** that the user later corrected:

- **Original framing:** k4k as a developer CLI tool — user runs `k4k <file>` with flags (`--check`, `--status`, `--reset`, `--max-steps`, `--budget`, `--verifier`, `--backend`), populates `k4k.backend.command` and `k4k.verifier.command` in YAML frontmatter, manages the working tree, and chooses verification level.
- **Corrected framing (`feedback.md` at repo root):** k4k as an autonomous coding agent — the user only writes free-form text in the `.k4k` file via cotype; k4k watches the file, asks clarifying questions in-line, and once a "version" of the spec is stable, develops + verifies in **full autonomy**. **The default verification tier is full formal verification** (Rocq+extraction; Frama-C/ACSL); testing/fuzzing is a degraded tier the user must explicitly approve.

The architectural commitments earned during v0 (cotype delegation per ADR-010, wire-protocol verifier/backend per ADR-008/009, canonical-AST determinism per ADR-005, two-layer KB per ADR-006, deterministic kb-regen per ADR-007) **survive both UX corrections** and were not affected by the drift. The drift is concentrated in the wrapper, frontmatter user-facing schema, and PRD/README framing.

## Why kept, not deleted

- The ADRs referenced from these files are still load-bearing; deleting the rationale trail breaks audit-ability of the architectural decisions.
- The Phase-5 audit reports document real bugs caught (e.g. the NF4 `/tmp` envelope violation in `audit-real-*`), which informed code that's still in the tree.
- Future contributors reading the active KB should be able to trace why decisions look like they do and why the v2 reorientation happened.

## Contents

| File | What it was |
|---|---|
| `questions-round1.md` | v0 Phase-1 ambiguity resolution, round 1. Drifted at Q1 ("v0 is a POSIX CLI named k4k that ... prints a one-line status with ETA"). |
| `questions-round2.md` | v0 Phase-1, round 2. Tightened Q13 (semantic stability) and Q17 (`.k4k/` as agentic-dev-kit-style KB). Both correct under v2. |
| `questions-round3.md` | v0 Phase-1, round 3. Pinned scratch-branch naming + `Backend_stub` model + TTY format. The first two correct; the TTY format dies under v2 (no developer TTY UX). |
| `plan.md` | v0 implementation plan, 4 vertical slices. Names `lib/Verifier_dune_ocaml` and `lib/Backend_claude` which were retrofitted out by ADR-008/009. |
| `audit-round1-2026-05-02.md` | Phase-2 KB-quiz audit. Validated the v0 KB structure; substrate decisions still right. |
| `plan-simulation-2026-05-02.md` | Phase-3 plan-simulation gate. Caught one real KB contradiction (T18 ownership-flip persistence) that's still fixed in code. |
| `audit-step4-2026-05-02-axis*.md` | Phase-5 dry-pass audit (7 axes). Marked 0 criticals which the skeptical-second-pass later refuted. |
| `audit-real-2026-05-02.md` | The skeptical-second-pass audit. Found 2 criticals + 7 highs. Drove the post-audit gap-closure commits whose code-level fixes (NF4 envelope, P12 cotype-via-not-flock, P14 KB-only ownership-flip, P16 incrementality, etc.) are still in the tree. |
| `sync-quiz-2026-05-02.md` | Phase-6 KB-sync quiz, 3/3 from KB-only access. The KB content it validated has since been edited (e.g. ADR-010 added). |

## Read these if

- You're investigating why a particular architectural decision exists.
- You're auditing whether the v2 reorientation accidentally broke an invariant the v0 process established.
- You're writing about the methodology and want a worked example of "spec-driven agentic development drifting and being corrected."

## Don't read these if

- You're working on k4k v2 itself. The active KB is at `kb/INDEX.md` (back up at `kb/`).
- You're trying to understand what the user-facing UX *is*. The active framing is in the post-cleanup PRD and README.
