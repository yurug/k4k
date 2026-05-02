---
id: conventions.testing-strategy
type: concept
summary: How tests are written, named, and organized in k4k — property-driven naming, three-tests-per-file rule, four kinds of tests (unit, integration, property-based, edge-case).
domain: conventions
last-updated: 2026-05-02
depends-on: [glossary, properties.functional, properties.non-functional, properties.edge-cases]
refines: []
related: [conventions.code-style, runbooks.audit-checklist]
---

# Testing Strategy

## Test framework

`alcotest` (matches the verifier's expectations from `external/dune.md`). `qcheck` (alcotest-qcheck binding) for property-based tests.

## Test naming convention

Every test name **must** start with the property it verifies:

| Test kind        | Pattern                                            | Example                                      |
|------------------|----------------------------------------------------|----------------------------------------------|
| Functional       | `P<id>_<slug>`                                     | `P5_non_regression_under_partial_patch`      |
| Edge case        | `T<id>_<slug>`                                     | `T15_sigint_during_agent_call`               |
| Non-functional   | `NF<id>_<slug>`                                    | `NF1_sigint_exits_within_5s`                 |

Slugs are `snake_case`, descriptive but compact. The verifier adapter (`external/dune.md`) uses the prefix to map test results back to property statuses.

## Four kinds of tests

### 1. Unit tests
- One test file per `lib/<module>.ml`: `test/unit/test_<module>.ml`.
- Mock dependencies. Use `Backend_stub` and `Verifier_stub` as DI inputs to higher-level modules.
- ≥ 3 tests per source file (matches the methodology's floor).

### 2. Integration tests
- One test file per scenario from `domain/prd.md#user-stories`.
- Run end-to-end with stubs (no real `claude` or `dune` calls).
- Stories `S1`..`S6` each have at least one integration test.

### 3. Property-based tests
- For every invariant in `properties/functional.md` whose statement quantifies over inputs ("for all interaction files ...", "for all ASTs ...").
- `qcheck` generators in `test/property/gen.ml`.
- Minimum 1000 iterations in CI; 100 in local quick mode.

### 4. Edge-case tests
- One test per T-entry in `properties/edge-cases.md`.
- Hand-crafted inputs that exercise exactly that boundary.
- T-tests live in `test/edge/test_T<id>_<slug>.ml`.

## Coverage targets

- **Property coverage:** every P-, NF-, T-entry has at least one test whose name references it.
- **Code coverage:** ≥ 80% line coverage measured via `bisect_ppx`.
- **Mutation testing:** not in v0; acknowledged gap.

## Stubs

`Backend_stub` and `Verifier_stub` ship as part of `lib/` (not `test/`) because they are also used by the production CLI's `--backend=stub` mode for reproducible demos.

`Backend_stub` supports a "weakness profile" — see `conventions/context-economy.md` and ADR-003. Configurable via env var or constructor argument.

## Determinism in tests

- Property-based tests use a **fixed seed** in CI (`qcheck --seed 42`) so failures are reproducible.
- Wall-clock-dependent tests use a `Clock_stub` injected as a dependency; never `Unix.time` directly.
- File I/O in tests goes through a `tmpdir` cleaned up in teardown; no relative paths leak.

## What tests must NOT do

- Hit the real `claude` binary or the real Anthropic API. CI runs offline.
- Assume `dune` is installed (use `Verifier_stub`).
- Touch `$HOME` or `/tmp` outside the per-test tmpdir.
- Take longer than 30 seconds individually (timeout enforced).

## Property-test ↔ test mapping table

The audit pass (`runbooks/audit-checklist.md`) checks that every entry in `properties/{functional,non-functional,edge-cases}.md` maps to ≥ 1 test. The mapping is computed by grepping test names for `P<id>`/`NF<id>`/`T<id>` prefixes; a property without a matching test is a critical finding.

## Agent notes

> **Tests are property evidence.** Naming `assert_dune_invocation_correct` is wrong even if the test does the right thing. The name is part of the contract: the verifier adapter reads it; the audit pass reads it; the next contributor reads it.
>
> **Three tests is a floor, not a target.** If a module has only the three obvious tests, it's probably under-tested. Look at the function for boundary cases, error paths, and concurrent-edit scenarios.

## Related files

- `properties/functional.md` — P-entries that drive functional tests
- `properties/non-functional.md` — NF-entries with measurement procedures
- `properties/edge-cases.md` — T-entries that drive edge-case tests
- `external/dune.md` — the test-name convention used by the verifier
- `runbooks/audit-checklist.md` — where coverage is verified
