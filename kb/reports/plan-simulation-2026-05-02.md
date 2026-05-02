---
gate: phase-3-plan-simulation
timestamp: 2026-05-02
auditor: Explore subagent (KB-only access)
plan: kb/plan.md
result: 4 questions to user; 1 KB contradiction fixed in place; 5 simulator misses
---

# Plan-Simulation Gate — Findings

## Summary

The simulator walked all 4 implementation steps end-to-end against the KB and produced 10 candidate ambiguities. After cross-checking each against the existing KB content:

- **1 was a real KB contradiction** (T18 vs. P14 vs. algorithms.md#ownership on whether the ownership flip rewrites the file). Fixed in place. Resolution: k4k *never* rewrites; ownership is computed at read time by hash comparison every run; preserves P1.
- **5 were simulator misses** — answers were already in the KB; the simulator did not locate them. Logged below for traceability.
- **4 are genuine gaps** that must be resolved before Phase 4 starts. Routed to the user as `kb/questions-round3.md`.

## Real contradiction (fixed)

### Ownership-flip persistence

**Symptom:** `properties/edge-cases.md#T18` (original) said "the file's frontmatter `owner` is rewritten to `user`". `spec/algorithms.md#ownership` said "do not regenerate" but did not commit on rewriting. `properties/functional.md#P14` said "flips ownership *for the run*" — ambiguous on persistence.

**Resolution:** Aligned all three on **"k4k never rewrites; ownership is recomputed every run from hash comparison"**. T18 updated. P14 wording is consistent. Algorithms.md needs no change. P1 is now strict (no exceptions).

## Simulator misses (no action needed)

- **JSON schema validator:** `external/dune.md` + `architecture/overview.md` imply `ppx_deriving`/`ppx_yojson` for round-trip validation. The OCaml type *is* the schema.
- **`usage.input_tokens + output_tokens` mapping:** `external/claude-code.md` already specifies sum, mapped 1:1 to budget units, retries on subprocess crash up to 3×.
- **Coverage checklist for `cli`:** `spec/data-model.md#coverage-checklists` already enumerates exactly 11 aspects with the "N/A with rationale counts as non-trivial; empty does not" rule.
- **Verifier output file names:** `spec/config-and-formats.md` already specifies `stdout.log`, `stderr.log`, `result.json` per `verifier-runs/<id>/`.
- **Property ID generation:** `spec/algorithms.md#property-ids` already specifies `"P" || sha256(aspect_path)[:7]`, with `-2`, `-3` counter on collision.

## Genuine gaps (routed to user)

Routed to `kb/questions-round3.md`:

1. Prompt template location (in-repo vs. `.k4k/`-customizable) and templating syntax.
2. Scratch git branch naming, cleanup on SIGINT, and pre-existing-name handling.
3. `Backend_stub` canned-patch model (configuration shape, where patches live, format).
4. TTY status line format and `-v` interaction.

Each has a proposed default consistent with the rest of the KB.

## Conclusion

Phase 3 plan-simulation gate yields 4 user-facing questions. Once those are resolved, Phase 4 can begin on Step 1.
