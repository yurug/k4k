---
id: adr-021
type: decision
summary: How k4k scales to large implementations while the human-reviewed spec stays KISS. The observational spec_rel is the ONLY human-signed artifact and stays flat regardless of implementation size. The implementation+proof scale on two implementation-side axes — (1) COMPOSITIONAL verification (run is a composition of certified components, each with an agent-proposed, kernel-checked FUNCTIONAL contract; the top proof composes the contracts; the ADR-020 methodology applies recursively, the skeleton gate generalizing to a module-interface gate), and (2) naive→efficient refinement. Component contracts are functional Coq relations (∀x. S x (f x)), not mini observational specs.
domain: architecture
last-updated: 2026-06-21
depends-on: [adr-020, adr-019, adr-016, notes]
refines: [adr-020]
related: [adr-013]
---

# ADR-021: Compositional certification — scale the implementation, keep the spec KISS

## Status
Accepted (2026-06-21). Refines ADR-020 (its structured methodology is applied *recursively* here).
Approved scope: write the architecture **and** prototype a two-component certificate (the contract
form is decided in this ADR).

## Context
Even under KISS, realistic targets (a `grep` clone, an `awk`-lite, …) have implementations far too
large for a single flat proof. The danger is subtle: if scaling the *implementation* inflates what
the human must review, we break principle #1 (a simple spec any SWE can review ⇒ a certified
component).

## The invariant we protect
**KISS pins the spec, not the code.** The observational `spec_rel`
(argv/stdin/files → stdout/stderr/exit) is the **only human-signed artifact**, and it stays flat no
matter how large the implementation grows. *All* scaling work is implementation-side; the
human-reviewed surface is **constant**. That is the property every decision below defends.

## Two implementation-side scaling axes (the spec is fixed)

### Axis 1 — compositional verification (modular decomposition)
- `run` becomes a **composition of certified COMPONENTS** (`parse_opts`, `compile_pattern`,
  `match_line`, `format_output`, …), each a Coq function with its own **contract**.
- **The ADR-020 methodology applies recursively.** The proof skeleton's "lemmas" *are* component
  boundaries; the **SKELETON GATE generalizes to a MODULE-INTERFACE GATE** — coqc checks that the
  top proof composes from the component contracts (as `Admitted`) **before any component is built**.
  Each component is then certified by the same structured method (recursively, or decomposed further).
- A **composition theorem** (the "glue") derives the top `spec_rel` from the component contracts.

### Axis 2 — naive→efficient refinement (ADR-020 Phase 5)
- We certify the **simplest correct** implementation (naive-first), not a perf-engineered one. A
  grep built *for proof-simplicity* is a few kloc of Coq (a verified regex matcher — Brzozowski
  derivatives / Thompson NFA — is ~1–3 kloc *including* proofs), **not** C-grep's ~20 kloc of
  Boyer-Moore / mmap / DFA-cache optimisation. Efficiency is an **opt-in, behaviour-preserving,
  separate** certificate (`run_fast = run`), applied only where a benchmark demands it.

The two axes are orthogonal and both implementation-side: decomposition makes a big proof tractable;
refinement makes a slow certified program fast — *neither touches the human-signed spec*.

## Contract form (DECIDED)
Internal component contracts are **functional Coq relations**: a component `f : A -> B` carries
`f_spec : A -> B -> Prop` plus a certificate `forall a, f_spec a (f a)`.

- **Why functional, not mini-observational.** Components are *functions*, not CLI programs — they
  have no argv/stdout/exit. Forcing the observational k4kspec form onto them is a category error.
  Functional relational contracts **compose cleanly**: the glue chains `f_spec` then `g_spec`.
- **Who owns them.** Component contracts are **agent-proposed and kernel-checked** — they are
  **NOT human-signed**. Only the top observational `spec_rel` is reviewed by the human. (Alternative
  considered: recursive mini-observational specs for sub-components — rejected as a forced fit /
  category error for non-CLI functions.)

## TCB / human-review impact
Unchanged from ADR-018/019: the human signs the **top observational `spec_rel`** and reads the TCB
manifest. Component contracts and the composition proof are **kernel-checked, not trusted**. Result:
implementation size ↑, human-reviewed surface **flat** — exactly the property we set out to protect.

## Prototype (this ADR's validation — Phase B)
A minimal two-component certificate `run = format ∘ core`:
- `core : list ascii -> list ascii` (a sort) with contract `Sorted ascii_le l' /\ Permutation l' l`;
- `format : list ascii -> string` (`string_of_list_ascii`) with contract `list_of (format l) = l`;
- top spec = sorted-permutation; `compose : forall arg, top_spec arg (run arg)` proves it by
  **chaining the two component contracts** — the glue.
Plus the **module-interface gate demo**: with `core`/`format` certificates left `Admitted`, the glue
still compiles (the architecture is kernel-valid *before* the components are proved). Lives at
`k4kspec/backend/poc/compose_sort.v` — validates the Coq-level composition machinery.

## Open / next (the agent-orchestration follow-on)
- **Wire compositional decomposition into the agent backend**: the agent proposes components +
  contracts + glue; the harness drives the module-interface gate, then certifies each component by
  the recursive structured method. (This ADR validates the *Coq-level* machinery; agent
  orchestration is the next build.)
- A **certified-component library** (a matcher, a parser, a numeral renderer) reused across targets.
- **Inter-component dependency ordering** when one component's contract feeds another.

## Grounding
CompCert / seL4 compositional refinement; refinement calculus (Back/Morgan); contract-based modular
verification (Dafny, Cogent). The k4k contribution: the **human-signed boundary is a single
observational spec**, with every internal contract agent-proposed and kernel-checked.
