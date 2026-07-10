---
id: adr-021
type: decision
summary: How k4k scales to large implementations while the human-reviewed spec stays KISS. The observational spec_rel is the ONLY human-signed artifact and stays flat regardless of implementation size. The implementation+proof scale on two implementation-side axes — (1) COMPOSITIONAL verification (run is a composition of certified components, each with an agent-proposed, kernel-checked FUNCTIONAL contract; the top proof composes the contracts; the ADR-020 methodology applies recursively, the skeleton gate generalizing to a module-interface gate), and (2) naive→efficient refinement. Component contracts are functional Coq relations (∀x. S x (f x)), not mini observational specs.
domain: architecture
last-updated: 2026-07-10
depends-on: [adr-020, adr-019, adr-016, notes]
refines: [adr-020]
related: [adr-013]
---

# ADR-021: Compositional certification — scale the implementation, keep the spec KISS

## Status
Accepted / **realized** (2026-06-21). Refines ADR-020 (its structured methodology is applied
*recursively* here). Architecture + Coq-level prototype + **agent-driven** orchestration all built
(`certify-agent --compositional`, commits `bee7000`/`fc41c36`/`ec74442`). Contract form decided below.

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

## Agent orchestration — REALIZED (2026-06-21)
`lib/agent_proof.ml:certify_compositional` (CLI `certify-agent --compositional`, commit `ec74442`):
PHASE A **decompose** — the agent proposes components (impl + functional contract), `run` as their
composition, and a glue proof — gated by the **module-interface gate** (coqc accepts the glue `Qed`'d
with the component certificates `Admitted`); PHASE B **certify each component** (drive the
`compK_correct` admits to 0, focused coqc feedback); PHASE C **assemble** + `certify_v` (the real,
no-admits certificate). It is ADR-020's structured method generalized to module boundaries.

**Results.**
- `bsort` (2 components) — claude split into `sort_chars` (contract `Sorted ∧ Permutation`) +
  `err_line` (contract `one_nonempty_line`); glue derives the top spec from both certificates.
- **`grepf` — a FIRST MULTI-MODULE grep-class certificate (5 components).** `certify-agent
  --compositional grepf` decomposed it into `comp_argc` (arg count), `comp_nofile` (file-absent
  test), `comp_match` (matching lines = filter-by-contains over `lines`), `comp_err` (error output),
  `comp_ok` (success output); `run` composes them; the glue proves the top observational spec from
  the **five component contracts alone** (`rewrite`/`exact` on the contracts). Module-interface gate
  passed attempt 1; 0 escape hatches; certified binary matched **39/39** inputs; `Print Assumptions`
  = Closed under the global context. The **human signs only the top `spec_rel`**; the five component
  contracts are agent-proposed + kernel-checked. Captured at `k4kspec/backend/poc/grepf_compositional.v`.

This validates multi-module **breadth** (a real module graph + contract-based glue) on a grep-class
program; **depth** (a component with a substantial internal proof) is shown separately (the sort
component in `bsort`, the multi-invariant `usort`).

## Breadth + depth + RECURSION — realized (2026-07-10)
**`grepsort`** (lines of FILE containing NEEDLE, sorted by the lexicographic `bytes_le` — laws
`sorted_lines` + `permutation` over line lists, under-determined stdout, input-pinned grep-like
exit) is the **first certificate with both axes in one target**, and it required realizing this
ADR's "recursive decomposition" item first:

- The monolithic component fill re-created ADR-020's failure shape at the module level and stalled.
  Replaced by the **recursive per-lemma fill** (`agent_proof.ml`, commit `da3dea9`): one
  `Lemma … Admitted.` span is agent-replaced and spliced at a time (≤3 focused attempts, per-lemma
  coqc feedback); a resisting lemma escalates ONCE to a kernel-gated skeleton whose Admitted
  helpers re-enter the same loop — ADR-020 applied recursively, bounded by a total call budget,
  with an honest per-lemma failure report on exhaustion.
- **Live cascade observed** (run 1, budget 24): the feared deep component — the lex **sort** —
  proved in 2 focused calls; the true depth was the **`lines`/`unlines`/`splitc` roundtrip**
  (valid only under a no-embedded-newline side condition the agent must discover). Run 2 closed
  GREEN in **12 calls, one escalation** after the algebra's POSIX semantics were documented in the
  prompt — documentation of the trusted vocabulary beat a bigger budget.
- Certificate: 4 components (`comp_err`/`comp_lines`/`comp_sort`/`comp_render`) + glue; agent
  invented a boolean lex comparator + insertion sort + the `Forall` no-newline side condition;
  statement-pin gate + `Print Assumptions` closed; 3+5 body-only tampers rejected; 17-case
  independent oracle (8-bit clean, duplicates kept) exact; fresh-agent audit GREEN incl. a proof
  that `bytes_le` is a total order and that the two laws pin the output uniquely (up to one
  trailing newline — accepted under-determination).

## The blessed-laws library — first slice realized (2026-07-10, commit `9d75932`)
grepsort's agent-proven `lines`/`unlines`/`splitc` lemmas were harvested into a **PROVED-LAWS
section of Kalgebra.v** (theorems about the audited-once definitions, kernel-checked at compile ⇒
**zero TCB growth**; `no_newline` is lemma vocabulary only), and the prompt blurb advertises them
("cite, do NOT reprove"). **The compounding is empirical** — same spec, same prover, three runs:

| run | harness state | outcome |
|---|---|---|
| 1 | undocumented algebra, budget 24 | FAILED — roundtrip cascade exhausted budget, 5 lemmas short |
| 2 | + POSIX semantics documented    | GREEN — 12 calls, 1 skeleton escalation |
| 3 | + blessed-laws library          | GREEN — **6 calls, 0 escalations**; every component first-try |

The proof that consumed run 1's entire budget became three lines (`apply lines_unlines. Qed.`);
the glue discharges the side condition by citing `lines_no_newline`. Certification effort
**amortizes across programs** through the library — each hard certificate mints lemmas that make
the next one cheaper.

## Open / next
- **Grow the library by harvest**: after each new certificate, move its general algebra lemmas
  (statements mentioning only Kalgebra defs + stdlib) into the PROVED-LAWS section.
- **Inter-component dependency ordering** when one component's contract feeds another.
- Deeper recursion stress: a target whose skeleton helpers themselves need skeletons routinely
  (grepsort needed depth 2 only in run 1).

## Grounding
CompCert / seL4 compositional refinement; refinement calculus (Back/Morgan); contract-based modular
verification (Dafny, Cogent). The k4k contribution: the **human-signed boundary is a single
observational spec**, with every internal contract agent-proposed and kernel-checked.
