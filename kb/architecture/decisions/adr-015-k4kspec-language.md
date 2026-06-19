---
id: adr-015
type: decision
summary: k4kspec — a dedicated, verifier-independent, SWE-readable observational specification language whose spec denotes a relation R ⊆ Input×Output; with a frame/footprint fs model, a closed total value algebra, static stability, two-stage elaboration through a prover-independent IR, and a pluggable artifact-class dimension. Demotes ADR-005's role.
domain: architecture
last-updated: 2026-06-19
depends-on: [glossary, adr-014]
refines: [adr-005]
related: [adr-016, adr-008, adr-012, adr-013]
---

# ADR-015: k4kspec — the observational specification language

## Status
Accepted (2026-06-19). Realizes ADR-014's "formal-but-readable spec". **Demotes ADR-005**: the determinism boundary moves from canonicalized agent output to the spec language itself, and two-run formalization is replaced by a static stability check (below).

## Context

Certification (ADR-014) needs a spec that a *generalist software engineer* can review **and** that drives a machine proof. Raw Rocq/ACSL needs proof engineers. The chosen resolution (over "write a readable fragment of the prover's own language") puts the readability burden on a **tool**, not the human: a dedicated language whose elaboration to the prover the SWE never has to read.

## Decision

1. **k4kspec is a dedicated, verifier-independent, SWE-readable specification language plus a trusted elaborator** that compiles a spec to the chosen prover's **statement only** (never proofs).

2. **Observational semantics.** The spec speaks only in the program's *observable* vocabulary, never the prover's — which avoids the model/reality gap. The v1 `cli` domain:
   - `Input  = { argv: list bytes; stdin: bytes; env: name ⇀ bytes; reads: path ⇀ bytes }`
   - `Output = { stdout: bytes; stderr: bytes; exit: int[0..255]; writes: path ⇀ bytes }`
   - The program is a total deterministic function `run : Input → Output`.

3. **The spec denotes a relation `R ⊆ Input × Output`** — the set of *acceptable* outputs per input — enabling deliberate under-specification ("stderr wording unspecified"). Correctness theorem: `∀ i. R i (run i)`. A singleton `R` is fully determined; under-specification is an explicit, visible opt-out.

4. **Surface forms, whose conjunction is the denotation:** guarded **CASES** on input (a decision table; guards must be **exhaustive** ⇒ totality), **LAWS** (relational ∀/∃ properties), **EXAMPLES** (concrete rows, statically checked against the denotation). **Guards must be computable booleans** (the stability checker decides exhaustiveness/consistency from them); **LAWS may be arbitrary propositions** (discharged by proof, not computed).

5. **Filesystem = frame + footprint.** The spec declares the paths it may read/write (argv-parametric allowed, e.g. *reads file at argv[1]*); everything outside the footprint is **framed** (provably unchanged) — yielding a free "touches nothing else" property and bounding spec size. Directory traversal/globbing is **out-of-fragment** in v1 (trips the spec-simplicity budget → decompose or drop tier).

6. **Value algebra: closed, blessed, prover-realized, total, byte-first.** Every primitive is total (partial ops exposed only default- or option-valued). Text = a UTF-8 refinement reached via explicit `decode`. Authors compose blessed primitives only; `let` is abbreviation. (Open sub-decision, pinned in ADR-016: simple total lambdas vs named combinators for bulk ops.)

7. **Stability is a static, deterministic check** (replaces ADR-005's two-run formalization): *parses + type-checks + guards exhaustive + consistent (no input forced to an empty acceptable set) + examples agree + footprint in-fragment.* No agent judgment; decidable. ADR-016 adds the anti-vacuity dual (reject over-permissive `R`).

8. **Two-stage elaboration:** surface k4kspec → a **prover-independent semantic IR** (shaped by the artifact-class plugin) → a concrete prover (Rocq for v1; ACSL/Lean later). Classes × provers compose **additively** in code. The blessed value algebra lives in the IR, realized once per prover.

9. **Artifact class is a plugin dimension** (like the verifier and backend, ADR-008/009). A class plugin supplies:
   - **P1 signature schema** — operations, optional abstract state + invariants, trace shape (`one-shot | sequential | concurrent`);
   - **P2 class vocabulary** — the blessed-algebra extension;
   - **P3 semantic target** — acceptance predicate, correctness-theorem template, coverage/totality obligation, example-discharge (all prover-independent, targeting the IR);
   - **P4 I/O shim** — the trusted real-world ↔ model bridge, audited once per class×prover, **frame-enforcing**.

   v1 ships **one** plugin: `cli` (one-shot, no abstract state). Roadmap by semantic distance: CLI → pure library → stateful ADT → server/daemon → UI (UI needs a temporal/concurrency layer; deferred, **not precluded**). P1/P2/P3 are prover-independent; only P4 and the per-prover realizations are prover-specific.

## Consequences

- **Determinism done right.** Stability is now decidable and agent-judgment-free — a cleaner realization of the founding determinism principle than ADR-005's two-run-and-compare.
- **The elaborator is in the TCB.** It translates the certification anchor; a mistranslation makes the kernel prove the wrong theorem. ADR-016 requires statement-preservation.
- **Worked surface examples** (illustrative, not normative): `echo-tiny`, `head1` (argv-parametric file read, frame), and the paper-validated `intstack` (the `lib` plugin, level-2 state machine — evidence the class abstraction does not special-case CLI).

## What this means for implementers

- Never let the spec mention prover concepts. If a spec needs a concept outside the observable vocabulary or the blessed algebra, that program is out-of-fragment — surface the simplicity-budget breach, do not extend the surface ad hoc.
- The IR is the contract between the class plugin and the prover backends. Adding a class touches a plugin; adding a prover touches a backend; neither touches `Gap_step`/`Version_loop`.
- Treat reviewability of the surface as a first-class, measured property (the spec-simplicity budget), analogous to the codebase's file/function size caps.
