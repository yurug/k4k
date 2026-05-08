---
audit: axis-5-spec-compliance
timestamp: 2026-05-08T17:33:49Z
result: fail
---

# Findings — Axis 5 Spec Compliance

## Per-check results

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Every algorithm step in `spec/algorithms.md` is implemented exactly once | **fail** | top-level loop in spec is stale wrt v2 watcher; see Critical-1 |
| 2 | `spec/data-model.md` schemas match runtime | **fail** | manifest, characterization both drift; see Critical-2 / High-2 |
| 3 | Closed error taxonomy (P7): emit sites cross-checked against `spec/error-taxonomy.md` | **fail** | E_budget / E_max_steps still emit; see Critical-3 |
| 4 | Section IDs in `spec/config-and-formats.md` match the parser | **pass** | `lib/parser.ml:34-38` enumerates exactly the 9 ids in `spec/config-and-formats.md:122` |
| 5 | `api-contracts.md` signatures match `.mli` | **pass** (with caveat) | shapes match modulo cosmetic placement; see Low-1 |
| 6 | No undocumented CLI flag — `--help` vs `domain/prd.md#command-surface` | **pass** | test-only flags are documented in `kb/runbooks/test-environment.md`; PRD §command-surface explicitly tolerates `-v`/`-vv` |

Result: **3 fails, 3 passes** ⇒ axis fails (binary criterion per `kb/runbooks/audit-checklist.md:107`).

## Critical

### C1 — `spec/algorithms.md` top-level loop is pre-ADR-011 (still references exit-1, --max-steps, --budget, --reset)
- evidence:
  - `kb/spec/algorithms.md:30` — `if not stability.is_stable: ...; exit 1` — but v2 watcher (`lib/watcher_loop.ml:74-80`, `on_unstable`) appends a clarification block and **continues polling**. ADR-011 §1 / `kb/spec/error-taxonomy.md:78` (EUNSTABLE) explicitly says this no longer exits.
  - `kb/spec/algorithms.md:32-33` — `if G is empty: print "done"; exit 0 ... if --max-steps reached or budget exhausted: exit 4` — but `bin/main.ml` exposes no `--max-steps` / `--budget` flags, and `Watcher.run` only returns 0 on graceful shutdown / 1 on startup-phase error / 5 on PID collision (`lib/watcher.ml:101-126`).
  - `kb/spec/algorithms.md:179` — `Full regeneration only on --reset` — `--reset` does not exist anywhere in `bin/main.ml`; not in cmdliner registration (`bin/main.ml:17-74`).
  - `kb/spec/algorithms.md:200` — `--max-steps N: hard limit on gap-step iterations` — flag not present; `Run_loop` (which still raises `E_max_steps`) is unreachable from `bin/main.ml` and is exercised only by `test/unit/test_unit.ml`.
- fix: KB wins by default per CLAUDE.md, but here the **code is correct** (it implements ADR-011/013). Update `kb/spec/algorithms.md` lines 23-35 to reflect the watcher loop (poll cotype → stability → on Unstable append clarification + continue → on Stable run version-loop → repeat until SIGINT). Replace the `Termination` section (lines 198-202) — the only termination paths in v2 are SIGINT / SIGTERM, startup-phase error, and the test-only exit-on-* flags. Drop the `--reset` clause in `#kb-regen` (line 179).

### C2 — `Manifest` runtime omits `current`, `gap`, `budget`, `kb_source_map`, `retention`
- evidence:
  - spec: `kb/spec/data-model.md:87-99` enumerates 10 manifest fields including `current: { path, hash, last_verified_at }`, `gap: { path, hash, count }`, `budget: { soft_per_step, hard_per_invocation, used }`, `kb_source_map: { ... }`, `retention: { agent_runs_keep, verifier_runs_keep }`.
  - code: `lib/manifest.ml:85-108` (`build`) writes only `k4k_version`, `agent_backend`, `verifier`, `interaction_file`, `desired`, `last_run`, optionally `cotype`. The five fields above are silently absent.
- fix: ambiguous — both sides moved. v2 architecture (ADR-013) introduced per-version manifests at `.k4k/version/<n>/manifest.json` (`lib/version_persist.ml:37-60`) which absorb some of the gone state (notably `tier_assignments`, branch refs). The remaining fields (`gap`, `budget`, `kb_source_map`, `retention`) are simply unimplemented in v2.
  Recommended: KB wins. Update `kb/spec/data-model.md`'s `Manifest` schema to reflect the v2 shape — drop `gap` / `budget` / `kb_source_map` / `retention`, document the fields that are actually written (`agent_backend`, `verifier`, `interaction_file`, `desired`, `cotype`), and cross-link the per-version manifest schema (currently undocumented in `data-model.md`) introduced by ADR-013.

### C3 — Code raises `E_budget` and `E_max_steps`; spec says they were removed in v2
- evidence:
  - spec: `kb/spec/error-taxonomy.md:80-81` — *"(removed in v2) EBUDGET / EMAXSTEPS — Budget and step bookkeeping are no longer user-visible exit codes."*
  - code: `lib/error.ml:25-26` defines both constructors; `lib/run_loop.ml:89-93` raises both; `lib/stability.ml:106` raises `E_budget`. `Run_loop` is unreachable from `bin/main.ml` but the error catalog still claims them as user-facing exit codes (`lib/error.ml:50` maps both to exit 4).
  - cross-cutting: `lib/error.ml` is missing `E_ownership_violation` (spec `kb/spec/error-taxonomy.md:113-117` lists `EOWNERSHIP_VIOLATION` in the closed catalog with exit 64).
- fix: KB wins, but with care — the residual usage in `Stability.run_formalize` (line 106 — raised when *both* formalization runs blow the budget at parse time) is real. Two options:
  1. Demote `E_budget` / `E_max_steps` to internal-only events (no exit code), and rewrite the residual `Stability.ml:106` site to instead surface a clarification block via cotype (matching ADR-011 §"Budget bookkeeping → tracked internally; surfaces as a status update or trade-off proposal").
  2. Restore the spec entries with a "startup-phase only" caveat and keep the constructors. The spec author explicitly removed them in v2 (commit history shows the deliberate change), so option 1 aligns with intent.
  Either way, also add `E_ownership_violation` (or formally remove it from the spec catalog — but `lib/error.ml:20`'s `Invariant_violation` exception probably absorbs the responsibility, in which case spec should call that out).

## High

### H1 — `Characterization.t` schema in code carries `language` + `verifier_command` (ADR-012 §1) but `spec/data-model.md` does not document them
- evidence:
  - code: `lib/characterization.mli:88-96` adds two required fields under ADR-012 with explicit `(** ADR-012 §1: ... *)` callouts; canonicalization includes them in the hash (per ADR-005 / ADR-012's two-run-equivalence claim).
  - spec: `kb/spec/data-model.md:49-62` defines `Characterization` with no `language`, no `verifier_command`. `verifier_pref: string?` survives but is functionally dead (`lib/characterization.ml`'s `empty` defaults it to `None`; nothing else writes to it).
- fix: KB wins. Add the two fields to `kb/spec/data-model.md`'s Characterization schema with the ADR-012 cross-reference; consider deleting the orphaned `verifier_pref` field or marking it deprecated.

### H2 — Frontmatter parser still extracts `verifier_command` / `backend_command`, contradicting ADR-011 §1 / `spec/config-and-formats.md:97-101`
- evidence:
  - spec: `kb/spec/config-and-formats.md:99-101` — *"No tooling configuration is exposed to the user. The frontmatter has only `k4k.version` and `class`."*
  - code: `lib/parser_frontmatter.ml:135-163` extracts `k4k.verifier.command`, `k4k.verifier.timeout_s`, `k4k.backend.command`, `k4k.backend.timeout_s`; `lib/parser.ml:35-38` exposes them on `frontmatter`. Optional, so legitimate v2 files with only `version`/`class` parse fine — but the surface area is still there and `bin/main.ml` does not validate against unexpected keys.
- fix: ambiguous. Code is "additive" (these are *parsed but not required*), but the spec is normative ("**only** version and class"). Two paths:
  1. Strip the `verifier_command` / `backend_command` extraction from `parser_frontmatter.ml` and the corresponding fields from `Parser.frontmatter` (low risk: nothing in `lib/` other than test legacy reads them — check `grep frontmatter.verifier_command lib/`).
  2. Soften the spec to "v2 ignores tooling-configuration frontmatter; for forward-compat the parser tolerates pre-ADR-011 keys without honoring them" — and note in `parser_frontmatter.ml` that the extraction is dead-store.
  Recommended: option 1. The fields are not consumed (`bin/main.ml` builds `Watcher.config` without consulting them; `Watcher` does not see them), so deleting is mechanically safe.

### H3 — `k4k_version_string` is "0.1.0" in manifests but `bin/main.ml` advertises "0.2.0"
- evidence:
  - `lib/manifest.ml:4` — `let k4k_version_string = "0.1.0"` (also written into `.k4k/manifest.json` and validated against on read)
  - `lib/version_persist.ml:46` — `"k4k_version", \`String "0.1.0"` in per-version manifests
  - `bin/main.ml:78` — `Cmdliner.Cmd.info "k4k" ~version:"0.2.0"` — what `k4k --version` reports
  - `lib/full_check.ml:144` — `"0.1.0-unknown"` fallback
  - `lib/backend_stub.ml:22`, `lib/verifier_stub.ml:5` — `"0.1.0-stub"`
- fix: code-only change. Pick a canonical version constant (e.g. centralize in `lib/version_string.ml` or just `Manifest.k4k_version_string`), bump it to `0.2.0` to match the cmdliner string, and have `bin/main.ml` reference it. Otherwise the manifest version-mismatch validator (`lib/manifest.ml:13-19`) will reject any manifest written by the next bumped build, breaking forward compat.

## Medium

### M1 — `Property.bump_failure` keeps `blocked = fc >= 3`, but the v2 workflow renamed this signal to `Tradeoff`
- evidence:
  - spec: `kb/spec/algorithms.md:147-160` — `failure_count >= 3 ⇒ Tradeoff` (was: blocked); `Property.blocked` is described as "mirror of failure_count >= 3" in `kb/spec/data-model.md:31` but the *behavior* triggered changed.
  - code: `lib/property.ml:83-85` still sets `blocked` at fc=3; `lib/gap_step.ml:80-83` correctly returns `Tradeoff` (not `Blocked`) at fc=3 — but `lib/gap_step.ml:182-185` *also* short-circuits to `Blocked` if `p.blocked || p.failure_count >= 3` is already true at preflight. So a property reaches fc=3 once → emits `Tradeoff` once, then sticks as `Blocked` forever after rather than re-proposing.
- fix: code-side. Either (a) drop the `blocked` field entirely (it's now a synonym of `failure_count >= 3`, and the *meaning* should be "awaiting tradeoff resolution"), or (b) introduce a separate `tradeoff_open: bool` and have the preflight short-circuit on that, leaving `blocked` for genuinely-stuck (operator-marked) properties. Update `spec/data-model.md:31` accordingly so `failure_count >= 3` and `blocked` and "tradeoff awaited" are no longer conflated.

### M2 — Spec error-taxonomy table (lines 22-30) lists only exit codes 0/1/5/64+ but the catalog body lists 2, 3, 4 still in use
- evidence:
  - spec table: `kb/spec/error-taxonomy.md:22-30`
  - spec catalog: `kb/spec/error-taxonomy.md:84-105` keeps EAGENT_UNAVAILABLE→3, EVERIFIER_UNAVAILABLE→2, EVERIFIER_TOOL_ERROR→2, EDISK_FULL→4
  - code matches the catalog: `lib/error.ml:40-52` preserves exit codes 2/3/4 for those errors.
- fix: spec is internally inconsistent. KB wins → reconcile: either expand the table to include 2/3/4 (with a column "startup-phase / runtime") or fully demote 2/3/4 errors to in-file events per ADR-011 (same path as EBUDGET/EMAXSTEPS). The code currently follows the catalog, not the table.

### M3 — `lib/parser.mli`'s `frontmatter` type leaks the obsolete optional fields into the public API
- evidence: `lib/parser.mli:35-39` lists `verifier_command`, `verifier_timeout_s`, `backend_command`, `backend_timeout_s` as documented public fields. ADR-011 / spec/config-and-formats.md says these should not be in the v2 frontmatter shape at all.
- fix: pairs with H2. Removing from the `.mli` requires no callers (verified via grep — only `parser_frontmatter.ml` and the parser.ml indirection touch them).

## Low

### L1 — `Agent_backend.S` / `Verifier.S` shape: `type response` / `type result` placement differs from `spec/api-contracts.md`
- evidence: spec `kb/spec/api-contracts.md:64-71` puts `type response` *inside* the module type; code `lib/agent_backend.ml:11-15` puts it at top-level alongside the signature. Same for `Verifier.S` (`lib/verifier.ml:8-21` vs `kb/spec/api-contracts.md:121-129`). Functionally identical (the signature is sharable both ways), purely cosmetic.
- fix: spec-side. Update the spec snippets to mirror the actual shape so a reader copy-pasting can directly compile.

### L2 — `lib/property.ml:55-59` `uncertainty_of` includes a `\`Required -> 1.0` and `\`Established -> 0.0` arm; spec says "1.0 if unknown else 0.5"
- evidence: `kb/spec/algorithms.md:111` vs `lib/property.ml:55-59`. Code's behavior is sensible (Established has zero risk, so it sorts last) but technically out of spec.
- fix: spec-side — extend the table in `algorithms.md#risk-score` to include `required`/`established` cases.

### L3 — `kb/spec/data-model.md:60` lists `verifier_pref: string?` but the field is dead in code (assigned `None` only by `empty`)
- evidence: `lib/characterization.ml`, `lib/characterization_decoder.ml` — no read sites; `lib/characterization.mli:87` keeps the field for backward-compat.
- fix: pairs with H1. Either remove from spec or document as "deprecated; superseded by `verifier_command` per ADR-012".

## Notes

The dominant pattern across these findings is *spec lag*. ADR-011 / ADR-012 / ADR-013 reshaped v2's user surface in a single landing (commits `f47ebbb` … `5bcbeb3`) and the implementation work tracked the ADRs faithfully. `kb/spec/algorithms.md`, `kb/spec/data-model.md`, and `kb/spec/error-taxonomy.md` were partially updated for ADR-010 (cotype) but never received the post-ADR-011 sweep. The CLAUDE.md rule ("if the code contradicts the KB, the KB wins by default") applies *only when the spec is genuinely current*; ADR-011/012/013 are explicit, dated, and accepted-by-the-user, which makes them the actual normative source. Net effect: the bulk of the recommended fixes are spec edits, not code patches.

The single load-bearing finding is **C1** — the entire top-level loop in `algorithms.md` describes a non-existent codepath (`exit 1` on instability, `--max-steps`, `--reset`). A reader new to the project will write code following the spec and break v2's autonomous-watcher contract. This is the highest-priority paragraph to rewrite.

Two findings (C2, H1) actually obscure live functionality: someone reading `data-model.md` will not learn that `.k4k/version/<n>/manifest.json` exists or that `Characterization.language` / `verifier_command` are part of the canonical hash. Anyone debugging stability divergence (the formalization equivalence check, ADR-005 + ADR-012 §1) needs to know these fields participate in the hash.

The version-string drift (H3) is a small but concrete trap: bumping `bin/main.ml`'s `~version:"0.2.0"` advertises something the manifest validator rejects on read (`lib/manifest.ml:14-19` requires *exact* equality with `"0.1.0"`). A future "release v0.2.0" PR that fixes only the manifest constant will break every `.k4k/manifest.json` written by previous builds. Centralize the constant before that happens.

## Related files

- `kb/spec/algorithms.md` — the largest single-file edit needed (Top-level loop + Termination + KB-regen-on-reset)
- `kb/spec/data-model.md` — Manifest schema rewrite + Characterization schema (add `language`, `verifier_command`)
- `kb/spec/error-taxonomy.md` — reconcile the table vs catalog; explicitly note EBUDGET/EMAXSTEPS/EOWNERSHIP_VIOLATION status under v2
- `lib/error.ml` + `lib/run_loop.ml` + `lib/stability.ml:106` — code site for C3 cleanup (or spec restoration)
- `lib/manifest.ml:4` + `bin/main.ml:78` — version-string unification (H3)
- `lib/parser_frontmatter.ml:135-163` + `lib/parser.mli:35-39` — frontmatter cleanup (H2/M3)
- `lib/property.ml:83-85` + `lib/gap_step.ml:80-86,182-185` — blocked/tradeoff disambiguation (M1)
