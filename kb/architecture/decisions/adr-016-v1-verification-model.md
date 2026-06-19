---
id: adr-016
type: decision
summary: v1 verification model. Pin one prover (Rocq + extraction to OCaml); defer agent toolchain self-selection; qualify "certified" with a per-certificate TCB manifest; add executable spec-vs-intent validation, an anti-vacuity stability obligation, a statement-preserving elaborator, and counterexample feedback. Incorporates the 2026-06-19 expert panel. Revises ADR-012.
domain: architecture
last-updated: 2026-06-19
depends-on: [glossary, adr-014, adr-015]
refines: [adr-012]
related: [adr-008, adr-013, properties.non-functional]
---

# ADR-016: v1 verification model + assurance refinements

## Status
Accepted (2026-06-19). **Revises ADR-012** (agent-driven toolchain selection is deferred for v1). Incorporates the 10-expert verification panel, `kb/reports/expert-panel-2026-06-19.md`.

## Context

The panel's unanimous verdict: **the proof is the easy leg; trust collapses onto the human-signed spec and the unverified perimeter** (elaborator, I/O shim, value algebra, extraction). The v2 design over-built the prover gate and under-built spec-*validation* and TCB honesty. This ADR pins the v1 stack and mechanizes the refinements that defend leg (a) of ADR-014's trust argument.

## Decision

1. **Pin ONE prover for v1: Rocq (Coq) + extraction to OCaml.** Team-native; matches the extracted-from-a-proof model; OCaml artifacts. **Agent toolchain self-selection (ADR-012) is deferred** — additional provers arrive later as *audited plugins* (a prover backend + its I/O shim + its elaborator lowering), never stochastic per-project picks. Rationale: self-selection makes the TCB the union of N kernels + N shims + N extraction paths.

2. **"Certified" is qualified; every version ships a TCB manifest.** A Tier-A certificate asserts: *"the implementation is proven to satisfy the human-signed observational spec, modulo {Rocq kernel, extraction, OCaml runtime, the blessed value algebra, the I/O shim, the elaborator}."* **Extraction is named explicitly** as an unverified trusted step (the panel's specific critique of the Rocq path). The manifest lists every TCB component, its version, and its audit date, per certificate.

3. **Executable spec-vs-intent validation phase (highest-leverage panel item).** Because `R` is executable (totality via exhaustive guards), the harness compiles k4kspec to an oracle and **differentially / adversarially / property-based-tests `R` *before* attempting any proof**, and differentially tests the **extracted binary** against the oracle (this is also what pragmatically mitigates the extraction hole). Auto-mined counterexamples *outside* the author's EXAMPLES are surfaced to the human to adjudicate. **Validation (is `R` what was meant?) is distinct from verification (does the impl satisfy `R`?)** and is a first-class harness phase.

4. **Anti-vacuity obligation, added to stability** (the dual of ADR-015's consistency check): require a satisfiability witness and **at least one rejected output per case** (a negative witness); **dead guards and never-satisfied law-hypotheses are stability ERRORS**. Guards against an over-permissive `R` that a stochastic patch-search would reward-hack.

5. **Statement-preserving elaborator.** The elaborator must emit, alongside the prover statement, evidence that the statement denotes the *same* `R` as the signed surface — a kernel-checked adequacy lemma, or at minimum property-testing against a reference denotational semantics of k4kspec. Removes the one TCB component sitting directly between the signature and the proof.

6. **Counterexample/diagnostic feedback into the agent loop + a cheap incorrectness pre-gate.** The founding *efficiency* axiom is earned here: pipe prover counterexamples and diagnostics back into agent context; run a sound-for-bugs check on each proposed patch *before* spending Tier-A proof budget.

7. **k4kspec DSL discipline (Chlipala dissent).** Each surface form is prototyped as a *shallow prover library* first, and promoted to trusted k4kspec syntax only once (a) the library encoding is shown genuinely unreadable to SWEs **and** (b) statement-preservation for that form is proven. The new-language tax is a per-form, evidence-gated decision, not a blanket commitment.

8. **Bulk-ops sub-decision (OPEN).** Simple total lambdas restricted to blessed-primitive bodies (recommended — covers grep/cut/tr-class text tools) vs named combinators only. To be pinned during the value-algebra design.

9. **Non-observable obligations checklist (Chapman).** A per-certificate checklist — secret-erasure, constant-time, resource bounds — the engineer must **discharge or explicitly waive**. The observational functional `R` cannot state these, yet they decide whether a "certified" component is actually safe.

10. **Empirical reviewability study.** Measure the escaped-defect rate of *non-proof-engineers* reviewing wrong-but-well-formed k4kspecs (mutation testing on real specs). Readability of the anchor is a **hypothesis under test**, not an assertion; publish the number.

## Consequences

- v1 has **one auditable stack**; the word "certified" is honest (qualified by a manifest); the spec is *validated*, not merely *verified against*.
- The verification **tier extends to the perimeter**, not just per-property: a certificate declares the rigor of its elaborator/shim (proof-producing vs property-tested-against-reference-semantics). This is the knob that reconciles the panel's rigor-vs-automation split (Chlipala/Klein maximal-rigor vs Leroy/Pierce test-sufficient) — rigor becomes a declared, per-certificate attribute.
- Convergence is materially better than interactive-only Rocq once §3/§6 land (validation pre-filter + diagnostic feedback); without them, Gallina proof generation is the hardest path for the agent and the founding efficiency claim is unearned.

## What this means for implementers

- Build the **spec-validation phase early** — it is mostly test-harness plumbing, it de-risks the most (autoformalization), and it doubles as the extraction-hole mitigation.
- **Name extraction in every manifest.** Do not describe a Tier-A artifact as "certified" without the qualifying clause.
- **Do not re-enable toolchain self-selection** until each new prover ships with an audited shim and a statement-preserving elaborator lowering.
- The anti-vacuity and statement-preservation obligations are *blocking* — a spec that cannot exhibit a rejected output per case is unstable; an elaboration without adequacy evidence is not Tier-A.
