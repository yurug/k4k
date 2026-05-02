---
id: adr-004
type: decision
summary: Verifiers are pluggable via the same module-signature pattern as backends. v0 ships `dune-ocaml`. Rocq, Frama-C, Verus, AFL deferred to v1+.
domain: architecture
last-updated: 2026-05-02
depends-on: [domain.prd, spec.api-contracts]
refines: []
related: [adr-001, adr-003, external.dune]
---

# ADR-004: Pluggable verifier; v0 ships dune-ocaml only

## Status
Accepted (2026-05-02).

## Context
NOTES.md envisions multiple verifiers (Rocq, Lean, Verus, Frama-C, AFL) and the eventual ability for k4k to build its own. v0 must ship something concrete without committing to all of them.

A test-suite-based verifier is the lowest-friction starting point: it is *deterministic* (same source ⇒ same pass/fail), *complete* in a narrow sense (every property has a corresponding test), and *available everywhere* (every OCaml dev has dune).

## Decision
1. **The verifier is an OCaml module signature** (`Verifier` in `spec/api-contracts.md`).
2. **v0 ships exactly one implementation: `Verifier_dune_ocaml`** — runs `dune build @runtest`, parses the test output, maps `P<id>_*` test names to property statuses.
3. **The test-name convention is enforced *by k4k* when generating tests** (during gap-steps). The verifier adapter rejects malformed names with `T20`'s `verifier.warning`.
4. **`Verifier_stub`** ships from day one for tests of k4k itself.
5. **Future verifiers** plug in via the same signature; no harness changes.

## Consequences
- v0 supports only OCaml target programs. (Self-fulfilling: the verifier tests OCaml; the prompts ask for OCaml; the test convention is OCaml.)
- The "low formal-strength" critique of test-suite verification is real but acceptable for v0 — the harness's correctness story is *test coverage of every property*, which is rigorous enough to demonstrate the approach.
- The path to Rocq/Lean/Verus is clear: implement `Verifier_<tool>` against the same signature; map their proof-status outputs into the closed status enum.

## What this means for implementers
- **Adding a verifier is additive only.** If it requires changes to `Harness` or `Gap_step`, the signature in `api-contracts.md` is wrong; fix the signature first.
- **Test-name discipline:** the gap-step prompt template explicitly instructs the agent to name tests `P<id>_<slug>`. The adapter validates.
- **No verifier judgment leaks.** The `result.json` schema is the only signal. If a verifier emits "this looks suspicious" in stderr, that is for human eyes only — `Gap_step` ignores it.
