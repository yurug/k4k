---
id: external.dune
type: external
summary: Runtime behavior of `dune` as the v0 verifier — invocation, output parsing, exit-code semantics, test-name convention, failure modes.
domain: external
last-updated: 2026-05-02
depends-on: [glossary, spec.api-contracts]
refines: []
related: [adr-001, adr-004, conventions.testing-strategy]
---

# External: dune (OCaml verifier)

## One-liner

v0's only live verifier. Runs `dune build @runtest` (and `@check` when only typechecking is needed) on the target program; parses the test output to map `P<id>_*` test names to property statuses.

## Scope

What k4k actually expects from dune at runtime, not a re-statement of the dune docs. Captures observed quirks — exit-code interpretation, test-runner stdout shape, error-vs-failure distinction.

## Invocation surface

```
dune build @check                              # typecheck-only (used during patch screening)
dune build @runtest                            # build + run all tests (the property check)
dune build @runtest --force                    # invalidate cache (used after every patch)
```

For v0, k4k always uses:
- `--force` on `@runtest` after applying a patch (cache invalidation safety).
- `--display=quiet` to keep stdout machine-parseable (no progress prose).
- `--root <workdir>` to pin the build root.

## Process model

- One subprocess per verifier invocation.
- Startup cost: small (~50-200 ms cold, less if warm).
- k4k consumes stdout + stderr + exit code. No streaming.

## Test-name convention (k4k-specific contract)

Every test must be named `P<id>_<slug>` where `<id>` matches the property ID exactly (e.g. `P3a4b1c2_argv_handles_missing_required`). The verifier adapter:
1. Parses dune's test output (alcotest format expected; framework-specific adapters TBD).
2. For each test result line, extracts `P<id>` and the pass/fail status.
3. Maps to `Established | Contradicted | Unknown` per property.

Tests not matching the convention are surfaced as `verifier.warning` events (`T20`) but do not break the build.

## Output parsing

Default test framework: alcotest. **alcotest writes test results to `stderr`, not `stdout`** — observed empirically during step 3 implementation; not documented in upstream alcotest docs at the time of writing. The verifier adapter therefore scans both streams when parsing test results, with stderr being the primary expected location. Build errors (compiler / dune diagnostics) also appear on stderr; the parser distinguishes them from test results by line shape.

Its output looks like:
```
Testing `myproject'.
This run has ID `XXXXXXXX'.
  [OK]          Suite        0   P3a4b1_argv_handles_missing_required.
  [FAIL]        Suite        1   P5e6f7_stdout_is_utf8.
...
The full test results are available in `_build/default/_tests/...`
```

The adapter parses lines matching `^\s*\[(OK|FAIL)\]\s+\S+\s+\d+\s+(P\w+)_.*\.\s*$` and:
- `[OK]` → `Established`
- `[FAIL]` → `Contradicted`
- Property in `D` not seen in output → `Unknown`

Other test frameworks (ounit2, qcheck, …) are out of scope for v0.

## Exit-code semantics

| `dune` exit | Interpretation                                                 | k4k mapping                  |
|-------------|----------------------------------------------------------------|------------------------------|
| 0           | Build OK + all tests pass                                      | All listed properties → `Established` |
| 1           | Build OK + one or more tests failed                            | Per-property mapping from output |
| 1           | Build error (typecheck failure, missing dep)                   | `EVERIFIER_TOOL_ERROR` (parse stderr to confirm) |
| 2           | Internal dune error                                            | `EVERIFIER_TOOL_ERROR`       |
| 130         | Killed (e.g. SIGINT propagated)                                | Treat as `Tool_error` w/ "interrupted" |

The "1 means build error vs test fail" ambiguity is resolved by the parser: if no `[OK]/[FAIL]` lines appear at all, treat as build error.

## Request budget

dune itself has no cost; constraint is wall-clock. v0 budget:
- `dune build @check`: assume ≤ 5 s for a small project.
- `dune build @runtest --force`: assume ≤ 30 s for a small project.

A wall-clock cap (60 s default, configurable) is enforced via process timeout; on expiry, kill child and emit `EVERIFIER_TOOL_ERROR`.

## Failure modes

| Failure                                  | Detection                                | k4k action                                  |
|------------------------------------------|------------------------------------------|---------------------------------------------|
| `dune` not on `$PATH`                    | execvp ENOENT                            | `EVERIFIER_UNAVAILABLE`, exit 2             |
| OCaml compiler missing                   | dune stderr has "no installed compiler" | `EVERIFIER_UNAVAILABLE`, exit 2             |
| dune-project absent                      | dune stderr has "no dune-project file"   | `EVERIFIER_TOOL_ERROR`, exit 2              |
| Build error in newly applied patch       | Exit 1 + no `[OK]/[FAIL]` lines          | Reject the patch in `Gap_step`              |
| Hung test                                | Wall-clock > 60 s                        | Kill child; treat as `Contradicted` for the focus property |

## Determinism

dune builds are deterministic given a clean working tree. k4k enforces clean state by running on a scratch branch and using `--force`. Two consecutive runs on the same source must produce the same `result` — verified by the test suite's `NF6_determinism_under_repeat`.

## Side effects

- `_build/` is created in the workdir. k4k does **not** treat `_build/` as user-owned; it may be wiped freely.
- No global state mutations (provided opam env is configured per-user, not system-wide).

## Versioning

`dune --version` recorded in `manifest.verifier.version`. Major-version changes warrant a JSONL warning but do not invalidate state by themselves.

## Agent notes

> **The test-name convention is the wire contract** between k4k and dune. If a contributor uses `let%test "..."` (no name) or names a test in some other style, the verifier adapter cannot map it to a property — and the gap-step will mark the property `Contradicted` for the wrong reason. Lint check on the agent prompts: must instruct `P<id>_<slug>` discipline.
>
> **Don't add framework breadth in v0.** If a target program needs ounit2 or qcheck for some reason, declare that out of scope and revisit in v1. The point of v0 is one tight loop end-to-end.

## Related files

- `spec/api-contracts.md#verifier` — the signature
- `architecture/decisions/adr-004-verifier-extension.md` — why dune-only in v0
- `conventions/testing-strategy.md` — how property-driven tests are named and structured
