---
audit: axis-5-spec-compliance
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 5 (Spec compliance)

## Method

1. Algorithm-step coverage: each spec anchor in
   `kb/spec/algorithms.md` has a corresponding implementation:
   - `#stability` — `Stability.check_structural`,
     `Stability.semantic_check_with_backend`
   - `#formalization` — `Stability.run_two` (in `Stability.ml`)
   - `#canonicalize` — `Canonicalize.canonicalize`
   - `#property-ids` — `Property_id.of_path`
   - `#gap-construction` — `Property.from_characterization`
   - `#risk-score` — `Property.risk_score` + `Property.severity_table`
   - `#gap-step` — `Gap_step.step`
   - `#kb-regen` — `Kb_regen.regen` / `Kb_regen.regen_full`
   - `#ownership` — `Kb_regen.is_owned_by_k4k`
   - `#concurrent-edits` — `Run_loop.restability_check`
2. `data-model.md` schemas: every type has a hand-written
   yojson encoder/decoder pair (`Characterization_json` /
   `Characterization_decoder`); round-trip tested by
   `P4_json_round_trip_preserves_hash` and `spec_json_validates_round_trip`.
3. Closed error taxonomy (P7): `Error.code_id` maps every variant of
   `error` to a documented ID. `Error.exit_code_of` returns 1..5.
   `P7_unique_code_id` and `P7_exit_codes_in_range` enforce.
4. Section IDs in parser: `Parser_sections` keys on user-section IDs;
   `EFORMAT_duplicate_id` and `T1_empty_file_is_unstable` enforce.
5. `api-contracts.md` ↔ `.mli` signatures: `Agent_backend.S` and
   `Verifier.S` are implemented by `Backend_stub`, `Backend_claude`,
   `Verifier_stub`, `Verifier_dune_ocaml`. The lint pass
   `code_style_no_Sys_command` runs across these.
6. `--help` ↔ `domain/prd.md#command-surface`: `--check`, `--max-steps`,
   `--budget`, `-v`, `-vv`, `FILE` — all match.

## Critical
(none)

## High
(none)

## Medium
- `algorithms.md#kb-regen` describes a per-file agent call (one call
  per affected KB file). v0 implements deterministic rendering instead
  (no agent), per the step-4 plan note "v0 deterministic rendering"
  in `kb_regen.ml`. This is a **planned divergence**, not a spec
  violation: future versions may wire `prompts/kb-regen.md` for an
  agent-driven rendering. The prompt template ships alongside.

## Low

## Notes

The spec ↔ implementation table:

| Anchor                              | Module / function                              |
|-------------------------------------|------------------------------------------------|
| `#stability`                        | `Stability.check_structural`, `..._with_backend` |
| `#formalization`                    | `Stability.run_two`                            |
| `#canonicalize`                     | `Canonicalize.canonicalize`                    |
| `#property-ids`                     | `Property_id.of_path`                          |
| `#gap-construction`                 | `Property.from_characterization`               |
| `#risk-score`                       | `Property.risk_score`                          |
| `#gap-step`                         | `Gap_step.step`                                |
| `#kb-regen`                         | `Kb_regen.regen`, `Kb_regen.regen_full`        |
| `#ownership`                        | `Kb_regen.is_owned_by_k4k`                     |
| `#concurrent-edits`                 | `Run_loop.restability_check`                   |
