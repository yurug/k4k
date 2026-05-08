---
audit: axis1-test-gap
timestamp: 2026-05-08T00:00:00Z
result: fail
---

# Findings — Axis 1 (Test gap analysis)

Per `kb/runbooks/audit-checklist.md#axis-1--test-gap-analysis`, six
checks were run against `kb/properties/{functional,non-functional,
edge-cases}.md`, the `test/{unit,integration,edge,conformance}/`
trees, and the public-function lists in `lib/*.mli`. Result:
**fail** (3 of 6 checks fail; 1 n/a; 2 pass).

The full set of 109 property-prefixed test names was extracted by:
`grep -hoE '"(P|NF|T|S)[0-9]+[a-z]?_[a-zA-Z0-9_]+"' test/**/*.ml |
sort -u` — see Notes for the full list.

## Score per check

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Every `P*` in `properties/functional.md` has ≥1 test starting with that ID | **fail** | P12, P21, P23 have **zero** tests prefixed by their ID. P12 is exercised under names `Cotype_save_*` (`test/unit/test_unit.ml:347-363`). P21 has only an `@invariant P21` mention in `lib/tradeoff_flow.mli:5` and no test (`grep -nE 'P21' test/` empty). P23 (toolchain agnosticism, ADR-012) has no test asserting the lint invariant; `Toolchain_install` is well-tested but tests are named `Toolchain_install_*` (`test/unit/test_unit.ml:2433-2528`). All 20 other P-IDs (P1–P11, P13–P20, P22) have ≥1 properly prefixed test. |
| 2 | Every `NF*` in `properties/non-functional.md` has ≥1 test or measurement | **pass** | NF1 (`test/integration:994`), NF2 (`test_unit:3439-3445`, including a `Slow` 50-step measurement), NF3 (`test_unit:3794-3796`), NF4 (`test_unit:3924-3930`), NF5 (`test_unit:3710-3714` poison-canary), NF6 (`test_unit:4059-4063`), NF7 (`test_unit:4328-4332`), NF8 (`test_unit:968-972`, `1224`). All eight NF-IDs covered. |
| 3 | Every `T*` in `properties/edge-cases.md` has ≥1 test prefixed `T<id>_` | **fail** | **T2, T15, T19** have no test by name and no by-topic hits (`grep -inE 'conflicting.*acceptance\|sigint.*agent\|aspect.*multiple'` empty). T2 is structural-stability boundary and the formalization-disagreement path *is* exercised by `T10_runs_disagree` and `T9_both_runs_invalid_json`, but the specific "two `examples_accept` entries with mutually contradictory expected outputs" trigger is not asserted. T15 (`SIGINT during agent call`) is *adjacent* to `T16_sigint_during_verifier_exits_within_5s` and `P8_signal_latency_under_stub` but the agent-call cancellation path (`HTTP/SDK abort, no agent-runs/<id>/ left half-written`) is unique and untested. T19 (`aspect → multiple properties`) has no test of the `Property_id` mapping in this dimension. T1, T3–T14, T16–T18, T20 all properly prefixed. |
| 4 | Every public function in `lib/` has ≥3 tests | **fail** (medium) | Genuinely thin coverage on these public functions: <br>• `Watcher_pid` (`lib/watcher_pid.mli:12-23`, 4 vals: `pid_path`, `acquire`, `release`, `pid_alive`) — **zero** test references. Single-instance enforcement (ADR-011 §2) is untested at the unit level. <br>• `Watcher_loop.run` (`lib/watcher_loop.mli:27`) and `Watcher.startup`/`Watcher.run` (`lib/watcher.mli:45,51`) — exercised only via the four `*Slow*` integration tests (`S1_watcher_drives_v1_to_completion`, `S5_*`, `P22_*`, `NF1_sigint_during_watcher`). No focused unit test of startup phases. <br>• `Version_finalize.finalize` (`lib/version_finalize.mli:30-41`) — exercised only via S1; both branches (`Done`/`Rolled_back`) need direct unit coverage. <br>• `Tradeoff_flow.propose_and_wait` (`lib/tradeoff_flow.mli:35-42`) — only the inline-blocks parser is tested (`test/unit/test_unit.ml:4794-4800`); the splice + poll loop is exercised only by S3 integration. <br>• `Manifest` (`lib/manifest.mli`, 6 vals) — only `Manifest.build` has a direct unit test (`test_unit:1459-1467`). `path`, `read_or_init`, `user_section_hashes`, `desired_hash`, `k4k_version_string` are exercised only indirectly. <br>• `Backend_external_parse` (`lib/backend_external_parse.mli`) — `parse` is exercised by the four `claude_code_*` and four `ollama_*` integration cases (`test/integration:1014-1033`); acceptable. <br>• `Status_splice.replace_or_append`, `Kb_render.render_file`, `Starter_template.render`/`auto_frontmatter` are pure renderers; covered indirectly via integration / Kb_regen tests but no direct unit tests. <br>Acceptable thin spots (single focused test plus integration coverage): the rest of the 56 modules. |
| 5 | Code coverage by `bisect_ppx` ≥ 80% | **n/a** | No coverage harness wired. `grep -inE 'bisect_ppx\|bisect\|coverage' dune-project lib/dune test/*/dune k4k.opam` empty. The opam `depends:` block has no `bisect_ppx` entry. **Finding:** there is no coverage harness yet — Phase-5 will need this added before this check can run. |
| 6 | No `xfail`/`skip` test without TODO referencing a tracked issue | **pass** (with caveat) | No `xfail` markers anywhere. There are 8 sites with `if not (cotype_available ()) then ()` (`test/unit/test_unit.ml:223-345` × 6 + `test/integration/test_integration.ml:107,178,211` × 2) that silently no-op when the `cotype` binary is missing. `cotype` is a runtime dependency of k4k itself (ADR-010), so on any well-formed dev env they execute; on this machine `which cotype` returns `/home/coder/.local/bin/cotype`. None of these are linked to a tracked issue but they are not classical `skip` markers either — they are runtime-dependency guards. **Caveat:** the silent `()` branch hides the case where a CI runner without cotype reports green — a `Logs.warn`/printed reason should at least make the skip visible (already done in `with_cotype` at `test/integration/test_integration.ml:106-108`; not done in unit tests). |

## Critical
_(none)_

## High
- **Axis1.H1 — P12 / P21 / P23 missing prefixed tests.** Three functional properties have no test starting with their ID; the audit's bookkeeping property (P20 itself enforces ID-prefixed tests as a discoverability convention) treats this as a hard violation.
  - evidence:
    - P12: `grep -nE '"P12_' test/**/*.ml` empty; existing tests are `Cotype_save_merged_when_concurrent_non_overlapping_edits` (`test/unit/test_unit.ml:354-356`) and `Cotype_save_conflict_when_overlapping` (`:357-358`).
    - P21: `grep -nE '"P21_\|P21' test/**/*.ml` empty; `lib/tradeoff_flow.mli:5` declares `@invariant P21` but no test asserts it.
    - P23: `grep -nE '"P23_\|P23' test/**/*.ml` empty.
  - fix: rename / add wrapper test_cases:
    - P12: re-export the existing cotype concurrency tests under a P12-prefixed Alcotest group, e.g. `P12_concurrent_writes_non_overlapping_merge`, `P12_concurrent_overlapping_yields_conflict`, `P12_user_clarification_edit_surfaces_conflict` (the third already exists as `T8_user_edits_clarification_section_surfaces_conflict` and serves both T8 and P12 — list it twice).
    - P21: add `P21_no_tradeoff_proposal_without_tier_a_attempt` exercising `Tradeoff_flow.propose_and_wait` against an empty `agent-runs/` directory — assert exception / refusal. (See `lib/version_tradeoff.ml` for the call site that already gates on a Tier-A failure outcome.)
    - P23: add `P23_lib_has_no_toolchain_specific_strings` as a Lint test running `grep -rE 'coqc|frama-c|verus|lean|extraction' lib/ | grep -v toolchain_install.ml` and asserting empty output. (The `Lint` module at `test/unit/test_unit.ml:4338` is the natural home; it already implements the P7/P20 lint patterns.)

- **Axis1.H2 — T2, T15, T19 missing tests.** Three edge-cases lack any test with their ID prefix.
  - evidence:
    - T2 (conflicting acceptance examples): `grep -inE '"T2_\|conflicting.*acceptance' test/**/*.ml` empty.
    - T15 (SIGINT during agent call): `grep -inE '"T15_\|sigint.*agent\|sigint.*backend' test/**/*.ml` empty; only T16 (verifier) and P8 (stub-latency, no agent backend) exist.
    - T19 (aspect → multiple properties): `grep -inE '"T19_\|aspect.*multiple' test/**/*.ml` empty.
  - fix:
    - T2: add a `Coverage` / `Stability` unit test feeding two `examples_accept` entries with the same `argv` but different expected `stdout`, assert `Stability.t = Unstable _` with a clarification mentioning both example ids. (Coverage check already exists at `lib/coverage.ml`; T2 is a missing scenario for it.)
    - T15: add an integration test mirroring `T16_sigint_during_verifier_exits_within_5s` (`test/unit/test_unit.ml:2569`) but signaling during a stubbed agent call — assert no `agent-runs/<id>/` directory survives (per the T15 spec at `kb/properties/edge-cases.md:111-113`). Use `Backend_stub` with a sleep hook.
    - T19: add a `Property_id` unit test that feeds an `errors` aspect entry with N=3 implications, asserts 3 distinct `P<id>` entries with the same `source.aspect` and different `source.path[]` (per `kb/properties/edge-cases.md:135`).

- **Axis1.H3 — `Watcher_pid` (single-instance enforcement) is completely untested.** ADR-011 §2 makes this safety-critical (mis-acquire ⇒ two watchers double-write to cotype). Zero unit tests; integration tests do not assert PID semantics either.
  - evidence: `grep -nE 'Watcher_pid\|pid_alive\|pid_path' test/**/*.ml` empty.
  - fix: add `module WPidT` to `test/unit/test_unit.ml` covering: `acquire` writes the file with our PID; `acquire` returns `Error` when a *live* PID owns it; `acquire` reclaims a stale PID file; `release` is idempotent; `pid_alive` correctly classifies our own PID and a clearly-dead one (e.g. `999999`). At least 5 `test_case`s; should run < 1 s.

## Medium
- **Axis1.M1 — No `bisect_ppx` coverage harness.** Check 5 cannot be evaluated. Without a coverage report the audit cannot detect "structurally exercised but never asserted" code paths.
  - evidence: `dune-project`, `lib/dune`, `test/*/dune`, `k4k.opam` contain no `bisect_ppx` reference.
  - fix: add `bisect_ppx` to `k4k.opam` `depends:` (with `with-test`); add `(instrumentation (backend bisect_ppx))` to `lib/dune` and the four test `dune` files; add a `make coverage` target invoking `dune runtest --instrument-with bisect_ppx` then `bisect-ppx-report html`. Target ≥ 80% line coverage on `lib/`.

- **Axis1.M2 — `Watcher.startup`, `Watcher_loop.run`, `Version_finalize.finalize` only exercised through `*Slow*` integration tests.** A single focused unit test per branch would catch regressions much earlier and run on every `dune test`.
  - evidence: `grep -nE 'Watcher\.startup\|Watcher_loop\.run\|Version_finalize\.finalize' test/**/*.ml` empty.
  - fix: add `module WatcherT` covering: `startup` on missing file creates the starter template; `startup` on existing-already-running PID returns `Already_running pid`; `startup` on a pre-existing well-formed file emits the expected JSONL events. Similarly add three direct unit tests for `Version_finalize.finalize` covering `Done` / `Rolled_back` / `Done with tier_dist` branches.

- **Axis1.M3 — `Manifest` accessors thinly tested.** Only `Manifest.build` has a focused unit test; `read_or_init` (which can raise `E_state_corrupt`), `user_section_hashes`, `desired_hash` are exercised indirectly.
  - evidence: `test/unit/test_unit.ml:1459-1467` is the only direct call.
  - fix: extend `module Smoke` (or split out a `ManifestT`) with: `read_or_init` round-trips a built manifest; `read_or_init` raises `E_state_corrupt` on `k4k_version` mismatch (already covered by `T17_stale_manifest_corrupt` — link by name); accessors return the values we wrote.

- **Axis1.M4 — `Tradeoff_flow.propose_and_wait` covered only by S3 integration.** The cotype-splice + polling loop has no unit-level test.
  - evidence: `test/unit/test_unit.ml:4758-4801` only tests the inline-block parser.
  - fix: add a `module TFRunT` with an in-memory `Cotype_stub` driving `propose_and_wait` to each of `Approved B`, `Approved C`, `Rejected`, `Timed_out` resolutions.

## Low
- **Axis1.L1 — Conditional cotype-skip in unit tests is silent.** When `cotype_available ()` returns false the unit-test branch returns `()` with no log line. The integration-test wrapper `with_cotype` (`test/integration/test_integration.ml:106-108`) at least prints `"skipped: cotype not on PATH"`; the unit tests should do the same.
  - evidence: `test/unit/test_unit.ml:238,253,267,279,307,336` all use the silent pattern.
  - fix: extract a `with_cotype` helper in unit tests symmetric to the integration one and have it `print_endline "skipped: cotype not on PATH"`.

- **Axis1.L2 — `Status_splice`, `Kb_render`, `Starter_template`, `Backend_external_parse` lack focused unit tests.** All are pure functions; tests would be a few lines each.
  - evidence: see Check 4 testref table above.
  - fix: one focused property test per function (round-trip / idempotence). Aim for 2–3 each.

## Notes

### Test-name canon (109 entries)

```
NF1_sigint_during_watcher_exits_within_5s NF2_rss_does_not_grow_unboundedly
NF2_rss_kb_reads_value NF2_rss_under_512mb_for_50_step_scenario
NF3_random_kill_iterations NF3_single_crash_is_atomic NF4_path_check_helper
NF4_state_confinement_envelope NF4_trace_disabled_by_default
NF4_verifier_external_no_tmp_writes NF5_scrub_handles_password
NF5_scrub_handles_token_keyword NF5_secrets_canary_never_leaks
NF6_determinism_under_repeat NF6_strip_ts_drops_known_fields
NF6_strip_ts_idempotent NF7_jsonl_replay_round_trip NF7_reconstruct_empty_log
NF7_reconstruct_only_persist NF8_formalization_under_weakness_profile
NF8_weak_response_differs_from_canned NF8_weak_response_is_parseable
P1_round_trip_byte_equality P1_user_section_byte_equality_under_save
P2_coverage_flags_missing_examples P2_coverage_passes_full_spec
P3_semantic_stub_passes_in_step_1 P3_stable_on_full_fixture
P3_unstable_when_section_blank P3_unstable_when_section_missing
P4_canonicalization_idempotent P4_canonicalization_preserves_structural_equivalence
P4_hash_differs_on_real_change P4_json_round_trip_preserves_hash
P4_no_identifier_renaming P5_gap_step_accepts_when_established
P5_non_regression_under_rejected_patch P6_bump_failure_blocks_at_3
P6_three_strikes_then_blocked P7_exit_codes_in_range P7_render_topical
P7_unique_code_id P7_unknown_error_is_invariant_violation
P8_signal_latency_under_stub P9_gap_step_budget_exhausted
P9_hard_budget_cap_terminates_gracefully P10_atomic_write_gap
P10_atomic_write_survives_simulated_crash P10_atomic_write_writes_content
P10_sha256_hex_known_vector P10_write_verifier_run
P11_debug_is_additive_over_verbose P11_jsonl_appends_event
P11_scrub_idempotent_on_plain P11_scrub_redacts_token P11_stdout_jsonl
P13_fresh_read_per_step P14_missing_file_is_owned P14_owned_when_hash_matches
P14_ownership_flip_on_user_edited_kb_file P15_strong_response_verbatim
P15_stub_canned_response_lookup P15_stub_name P15_stub_no_match_tool_error
P15_stub_step_1_default_tool_error P15_verifier_stub_focus_ignored
P15_verifier_stub_returns_ok P15_verifier_stub_version
P16_incremental_regen_only_touches_affected_files
P16_run_loop_does_not_rewrite_when_d_unchanged P17_argmax_lex_tiebreak
P17_risk_score_pure P17_unknown_outranks_contradicted
P17_unknown_outranks_contradicted_when_aspect_equal P18_equivalent_runs_are_stable
P18_two_run_minimum_detects_divergence
P19_cache_skips_formalization_when_hash_matches
P20_invariant_coverage_at_least_80_percent P20_invariant_ids_in_closed_set
P22_user_edits_queued_during_development P22b_v1_to_v2_picks_up_user_edits
S1_first_spec_first_run_e2e S1_watcher_drives_v1_to_completion
S3_tradeoff_proposal_signed_off S5_rollback_aborts_in_flight_version
S5_rollback_via_directive_in_status_block T1_empty_file_is_unstable
T1_empty_file_yields_clarification T3_pre_existing_partial_implementation
T4_initial_user_hashes_missing_file_empty
T4_initial_user_hashes_no_file_yields_empty T4_mid_run_edit_triggers_restability
T5_disk_full_during_atomic_write T5_disk_full_pattern_mismatch
T5_disk_full_unset_no_effect T6_non_utf8_rejected T7_at_cap_succeeds
T7_oversize_rejected T8_kb_file_hand_edit_flips
T8_user_edits_clarification_section_surfaces_conflict
T8_user_edits_tradeoff_section_surfaces_conflict T9_both_runs_invalid_json
T10_runs_disagree T11_verifier_unknown_for_all T12_three_strikes_blocked
T13_budget_exhausted_during_formalization T14_budget_exhausted_mid_step
T16_sigint_during_verifier_exits_within_5s T17_stale_manifest_corrupt
T17_stale_manifest_persists T18_user_overrides_target_kb_file
T20_warning_passthrough_emits_logger_event
```

### IDs missing from above (gap summary)
- P-series gap: **P12, P21, P23** (3 of 23). All have lib-side enforcement; only the *test-naming convention* is broken.
- T-series gap: **T2, T15, T19** (3 of 20). T2 needs a coverage-rejection test; T15 needs a signal-during-agent-call test; T19 needs a property-id-fan-out test.
- NF-series gap: none.

### What this audit does NOT cover
- Whether the existing tests **pass** — this audit only measures gap (presence/coverage), not correctness. A green `dune test` is assumed; if Axis 6 (Simplicity) reveals dead code, some of the "covered indirectly via integration" claims here may need re-examination.
- Mutation testing (would catch "tests exist but assertions are too loose"). Not in the checklist; raise as Phase-6 follow-up if Axis 1 closes.

### Single highest-impact fix
Add **`bisect_ppx`** instrumentation to `lib/dune` + `k4k.opam` and run the suite. The numeric per-module coverage report will reveal exactly which "thin" spots in Check 4 are *actually* unreached vs. covered through integration paths, turning Axis1.M2/M3/L2 from speculation into measured findings — and unblocks Check 5 permanently.

## Related files

- `kb/runbooks/audit-checklist.md` — the checklist
- `kb/properties/{functional,non-functional,edge-cases}.md` — what is being checked
- `kb/conventions/testing-strategy.md` — the convention `P<id>_*` test names follow
- `test/unit/test_unit.ml` (5106 lines), `test/integration/test_integration.ml` (1034 lines), `test/edge/test_edge.ml`, `test/conformance/test_conformance.ml` — the full test surface
