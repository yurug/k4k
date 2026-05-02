---
audit: phase-5-real-pass
timestamp: 2026-05-02
auditor: hostile reviewer (skeptical second pass; substantive, not structural)
prior_dry_pass: kb/reports/audit-step4-2026-05-02-axis*.md
result: 2 criticals, 6 highs
---

# Phase-5 Real Audit — k4k

## Method

Static, read-only inspection. For each axis the dry-pass (Phase-5 step-4)
checks were re-performed and, in addition, at least one new substantive
check was run. Every "pass" finding from the dry-pass was challenged by
trying to construct a failing case from the post-ADR-008 source. Where a
dry-pass conclusion no longer holds, the divergence is recorded.

---

## Axis 1 — Test gap analysis

### Findings

- **medium** — P-IDs that have no `P<id>_*`-prefixed test still:
  P8, P12, P13. Confirmed via `grep -nE 'P12_|P13_|P8_' test/`. The
  dry-pass listed these as medium; status unchanged. Each behavior
  *is* exercised indirectly (P8 by `T16_sigint_*`, P13 by
  `T4_mid_run_edit_*`, P12 by persist tests) but no named test asserts
  the named property. Fix: add `P8_signal_latency_under_stub`,
  `P12_concurrent_writers_serialize`, `P13_fresh_read_per_step`.
- **high** — `@invariant`s reference IDs not in `properties/functional.md`:
  - `lib/property.mli:73` `@invariant Property_id stability across runs.`
  - `lib/property_id.mli:11` `@invariant P_property_ids_stable_across_runs.`
  Per Axis-7 check 1 these violate the closed P-list (P1..P20). The
  dry-pass's "20/20" coverage table did not catch these because the
  lint walks `@invariant P<n>` only and quietly ignores non-numeric
  tails. Fix: rename to a valid P-ID or remove.
- **medium** — `lib/verifier.ml:3` and `lib/subprocess.mli:4` still
  reference the deleted `Verifier_dune_ocaml`. Stale doc post-ADR-008.
  Fix: replace with `Verifier_external` / `examples/verifiers/dune-ocaml/`.

### Notes
NF3/NF4/NF6/NF7 named tests verified present at `test_unit.ml:2728,
2811, 2944, 3213`. Coverage 17/20 P, 8/8 NF, 17/20 T (matches dry-pass).

---

## Axis 2 — Security

### Findings

- **critical** — **NF4 state-confinement envelope violation
  (post-retrofit).** `lib/verifier_external.ml:81` (`make_output_path`)
  selects `Filename.get_temp_dir_name ()` (i.e. `/tmp` or `$TMPDIR`)
  for the verifier's `--output` JSON file. `lib/git.ml:78`
  (`apply_diff`) uses `Filename.temp_file "k4k-gap-" ".patch"` which
  also lands in `/tmp`. NF4 forbids writes outside `<file.k4k>`,
  `.k4k/`, and the source tree. The dry-pass Axis-2 #3 claimed "every
  write parameterised by explicit path… only writes to .k4k/ and
  the working directory" — that is wrong post-retrofit. The
  `NF4_state_confinement_envelope` unit test (test_unit.ml:2762) uses
  `Verifier_stub` and never exercises `Verifier_external`, so the
  gap is hidden by the test selection. Fix: route both paths under
  `<k4k_dir>/scratch/<run_id>/` and add the env-violation case to
  the NF4 test.
- **low** — `Verifier_external` does **not** use the
  `K4K_TEST_TRACE_WRITES` hook for the `--output` path it owns, so
  even a fixed envelope would be invisible to the existing trace.

### Other checks
- `grep -r 'Sys.command' lib/` — empty (PASS).
- `grep -rE 'failwith|Failure ' lib/` — empty (PASS).
- All `Sys.getenv_opt` reads (`K4K_LIVE`, `K4K_STUB_*`,
  `K4K_FAULT_INJECT_ENOSPC`, `K4K_TEST_TRACE_WRITES`) are inside the
  closed set in `runbooks/test-environment.md` (PASS).
- `Subprocess.run` uses `Unix.create_process_env` — no shell
  interpolation, so no command injection (PASS).

---

## Axis 3 — Performance

### Findings

- **high** — **P16 incremental KB-regen is defeated at the call
  site.** `lib/run_loop.ml:126` calls
  `Kb_regen.regen ~prev_d:None ~current_d:d ...` after every accepted
  step. `lib/kb_regen.ml:55-59` returns *all* aspect names whenever
  `prev = None`; `files_affected_by` then yields every target file in
  `target_files`. Net effect: every accepted gap-step rewrites every
  k4k-owned KB file, regardless of which aspect actually changed. The
  static `kb_source_map` exists, but the run loop never feeds it a
  prior `D`. Dry-pass Axis-3 #6 said "P16 verifies the static map"
  — true at unit-test scope, but the production wiring nullifies the
  optimisation. Fix: thread `prev_d` through `Run_loop.run` (e.g.
  via a `ref` initialised from `cached_d` in `Convergence.run`).
- **medium** — `Run_loop.run` calls `Kb_regen.regen_full` once at
  start (line 155); the full pass is per ADR-007 reserved for
  `--reset`. After step-1 init this duplicates the per-step regen.

### Other checks
- Pre-call budget refusal exists at `Backend_claude.invoke` level
  (`P9_pre_call_budget_refusal` at test_unit.ml:962); the run-loop
  guard at `gap_step.ml:175` is `budget_now <= 0` rather than
  `used + this_call_budget > cap`, but T14 semantics are preserved
  via the per-call `~budget:budget_now` argument (PASS, marginal).
- `Backend_stub` weakness profile is `Strong` by default in
  `default_config`; tests that need NF8 enable `\`Weak` explicitly.
  Dry-pass said "weakness profile is the default in `dune runtest`"
  — that is wrong; the default is `Strong`. **medium**.

---

## Axis 4 — UX

### Findings

- **critical** — **PRD command-surface gap.** `bin/main.ml`
  (lines 31-58) ships only `--check`, `-v`, `-vv`, `--max-steps`,
  `--budget`, `--verifier`, `--verifier-timeout`. PRD §"Command
  surface (v0)" (`kb/domain/prd.md:50-58`) commits to **`--status`,
  `--reset` (with `--yes`), and `--no-color`** as v0 surface. None
  are implemented. Conversely `--budget`, `--verifier`,
  `--verifier-timeout` are *not* in the PRD command-surface table
  — undocumented surface. Fix either the PRD or `main.ml`; do not
  ship v0 with the gap.
- **high** — **`-vv` and `-v` are byte-identical.**
  `lib/logger.ml:88`: `| \`Verbose | \`Debug -> output_string stderr
  (scrub s ^ "\n")`. The `Debug` constructor has no behavioural
  effect; `logger.mli:17` claims "[`Debug] — also include subprocess
  details" but no call site differentiates. Axis-4 check #6
  ("`-vv` is additive over `-v`") fails. Fix: add a `details`
  channel only emitted at Debug, or wire stderr capture from
  `Subprocess` through a Debug-gated path.
- **high** — **Recovery hints missing from rendered errors.**
  `lib/error.ml:67-105` returns the body for each error variant,
  but most lack the recovery hint promised by
  `kb/spec/error-taxonomy.md`:
    - `E_file_not_found` → "file not found: %s" (no hint to verify
      relative path).
    - `E_file_too_large` → only states the size.
    - `E_encoding` → only states the offset.
    - `E_max_steps` → only states the count, no "raise --max-steps".
    - `E_budget` → has ".k4k/ left consistent" but no "raise
      `hard_per_invocation`" guidance.
    - `E_unstable` → only the issue list, no pointer to the
      appended clarification block.
  Axis-4 check #5 says "every error line contains either a path,
  a section id, or a recovery hint." Most contain a path/value but
  not a hint. Fix: extend `render_*` per the taxonomy column.

### Other checks
- `--check stable.k4k` prints exactly `stable\n` and nothing else
  (PASS, `S5_check_subcommand_exits_0_when_stable_structural`).
- stdout/stderr discipline (P11): preserved (verified at logger.ml,
  PASS).

---

## Axis 5 — Spec compliance

### Findings

- **high** — **P12 file-locking discipline is not implemented.**
  `grep -rn 'flock\|lockf\|Unix.lockf' lib/ bin/` returns empty.
  `kb/spec/config-and-formats.md:178-179` and
  `properties/functional.md#P12` mandate `flock(2)` on writes to
  `<file.k4k>`. `lib/persist.mli:31` says "P12 — write-only; the
  lock-discipline is enforced at the call boundary in [Harness]" —
  but no caller acquires a lock. The dry-pass Axis-7 marked P12
  "yes (Persist)" on the strength of the doc comment alone. Fix:
  add a real flock around any write to `<file.k4k>` (clarification
  appends are the realistic v0 case).
- **high** — Doc-only references to deleted modules in
  `lib/verifier.ml:3` and `lib/subprocess.mli:4` (see Axis 1).
- **medium** — `lib/full_check.ml:30` hardcodes
  `~verifier_version:"0.1.0-stub"` and never reads `V.version
  verifier`. Manifest's `verifier_version` field is therefore wrong
  for `Verifier_external` runs. Fix: thread the verifier value (not
  just the module) into `Full_check.run`, or version it via the
  `Verifier_external.config.command[0]` basename + a probe.
- **medium** — Algorithm anchor map updated for ADR-008: `#gap-step`
  → `Gap_step.step` (was `Verifier_dune_ocaml`); confirmed mapping
  holds.
- **low** — Closed-error-set check (P7): every variant in
  `lib/error.ml:3-17` has a corresponding entry in
  `kb/spec/error-taxonomy.md`. PASS.
- **low** — Frontmatter parser handles `k4k.verifier.command`
  (validated by `bin/main.ml:146-172`) per
  `config-and-formats.md` §"Frontmatter rules". PASS.

---

## Axis 6 — Simplicity

### Findings

- **medium** — `lib/persist.ml` is now **193 lines**, up from 170 at
  the dry-pass; still under 200 but the post-retrofit additions
  (`trace_write_path`, `K4K_TEST_TRACE_WRITES` plumbing) consumed
  the safety margin. Worth a split before the next change.
- **low** — `lib/gap_step.ml` (183) and `run_loop.ml` (176) are
  similarly close to the cap.
- **low** — `Git.init` and `Git.configure_test_identity` are public
  in `lib/git.mli` but used only by tests. They should remain
  public (tests need them) but document why in the .mli.

### Notes
File-length check `wc -l lib/*.ml`: max 193 (`persist.ml`), all ≤ 200.
No `failwith`/`Sys.command`. No genuinely dead module found.

---

## Axis 7 — Provability

### Findings

- **high** — Two `@invariant` annotations cite IDs that don't exist
  in `properties/functional.md`: see Axis-1 finding. The
  `P20_invariant_coverage_at_least_80_percent` lint passes only
  because it walks the *expected* P1..P20 list; it does not flag
  *unexpected* IDs. Fix: extend the lint to fail on unknown IDs.
- **medium** — `kb/architecture/overview.md:78` describes Persist as
  enforcing "flock(2) discipline" — the spec is correct but the
  implementation does not match (see Axis 5). KB↔code disagreement.

### Other checks
- Forbidden patterns (`agent.*ok|agent.*pass|model.*confirm`):
  empty in `lib/` (PASS).
- Every state-changing branch in `Gap_step.step` and
  `Run_loop.loop_iter` gates on verifier output, the budget ref, or
  the property's `failure_count`/`blocked` — no agent-judgment
  branches. PASS.
- KB cross-references (sample) resolve. The `external/dune.md`
  reference in `kb/spec/api-contracts.md:9` (`related: external.dune`)
  is **stale** post-ADR-008 (`external/dune.md` is gone). **medium**.

---

## Summary table

| Axis | Critical | High | Medium | Low | Notes (gaps the dry-pass missed) |
|------|----------|------|--------|-----|-----------------------------------|
| 1 — Test gap | 0 | 1 | 2 | 0 | Two `@invariant` IDs are not in P1..P20 — undetected by P20 lint. |
| 2 — Security | 1 | 0 | 0 | 1 | `/tmp` writes in `Verifier_external` and `Git.apply_diff` violate NF4 envelope. |
| 3 — Performance | 0 | 1 | 2 | 0 | P16 incrementality nullified by `prev_d:None` in run_loop; weakness-profile claim wrong. |
| 4 — UX | 1 | 2 | 0 | 0 | PRD command-surface gap (known); `-vv` non-additive (new); recovery hints missing (new). |
| 5 — Spec compliance | 0 | 2 | 2 | 2 | P12 (flock) not implemented at all; manifest verifier_version is hardcoded "stub". |
| 6 — Simplicity | 0 | 0 | 1 | 2 | persist.ml grew to 193 lines post-NF4 plumbing. |
| 7 — Provability | 0 | 1 | 1 | 0 | Architecture overview claims flock; unknown @invariant IDs slip past lint; one stale `related:` ref. |
| **Total** | **2** | **7** | **8** | **5** | |

(Axis-4 "high" count is 2 in the table because the PRD gap is the
critical row, not a high; the two highs are `-vv` and recovery hints.)

---

## Disagreements with dry-pass

1. **Axis-2 dry-pass**: "every write parameterised by an explicit
   path… only writes to .k4k/ and the working directory." False
   post-retrofit — `Verifier_external.make_output_path` and
   `Git.apply_diff` write under `Filename.get_temp_dir_name ()`.
   This audit raises the finding to **critical** (NF4 envelope
   violation).
2. **Axis-3 dry-pass**: "Backend_stub weakness profile is the
   default in `dune runtest`." False — `Backend_stub.default_config`
   is `\`Strong`; weakness must be opted into. (`medium`).
3. **Axis-3 dry-pass**: P16 "verifies the static map." Misleading
   — the unit test passes, but `Run_loop.loop_iter` calls
   `Kb_regen.regen ~prev_d:None`, so in production every accepted
   step regenerates *every* affected file regardless of which aspect
   changed. (`high`).
4. **Axis-4 dry-pass**: Implicitly claimed "`--help` matches PRD."
   It does not (the user's note is exactly this). The dry-pass
   row also missed that `-vv` does not differ from `-v`. (`high`).
5. **Axis-4 dry-pass**: "Error messages cite remediation." Most
   error variants do not contain the recovery hint promised by
   `error-taxonomy.md`. (`high`).
6. **Axis-5 dry-pass**: tacit assumption that P12 holds. P12 is
   not implemented at all (no `flock` call). (`high`).
7. **Axis-7 dry-pass**: "20/20 P-ID coverage." True for *expected*
   IDs, but two `@invariant` annotations cite IDs that *do not exist*
   (`P_property_ids_stable_across_runs`, `Property_id stability
   across runs`). The lint did not catch unknown IDs. (`high`).

---

## Bottom line

**Zero criticals does NOT hold post-retrofit.** Two real criticals:
the `/tmp` writes (NF4 envelope) and the PRD command-surface gap
(`--status`/`--reset`/`--no-color`). Seven highs span all seven
axes. The dry-pass was structural ("the lint passes, the test name
exists") rather than substantive ("does the wired-up production path
satisfy the property"); applying the substantive lens produces a
materially different picture.
