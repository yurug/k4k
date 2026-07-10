---
id: architecture.decisions.index
type: index
summary: Routing table for ADRs — significant design choices that survived ambiguity resolution, documented as decision records.
domain: architecture
last-updated: 2026-05-02
depends-on: []
refines: []
related: [architecture.overview]
---

# Architecture Decisions — Routing Table

## Convention

ADR format: Status, Context, Decision, Consequences, What this means for implementers. Each ADR is < 200 lines.

## Index

| ID      | Subject                                                                | Reason it exists                                                       |
|---------|------------------------------------------------------------------------|------------------------------------------------------------------------|
| ADR-001 | OCaml ≥ 5.1 + dune                                                     | Picks the language/toolchain for v0                                   |
| ADR-002 | Markdown interaction file with HTML-comment ownership tags             | Defines the user's contract format                                    |
| ADR-003 | Pluggable agent backend; design for the weakest supported model        | Locks in the Ollama-friendly architecture per round-2 user-added      |
| ADR-004 | Pluggable verifier; v0 ships dune-ocaml only                           | Sets the verifier extension point and v0 narrowing                    |
| ADR-005 | Determinism on canonical AST; two-run formalization · **DEMOTED→ADR-015** | Resolves the agent-stochasticity / harness-determinism tension; stability is now a static check on k4kspec |
| ADR-006 | Two-layer KB — meta (`kb/`) and target (`.k4k/`)                       | Pins down round-2 user-edit on KB layout                              |
| ADR-007 | Deterministic in-process kb-regen for v0                                | v0 deviates from `algorithms.md#kb-regen`'s agent-driven model        |
| ADR-008 | Wire-protocol verifier; k4k ships no verifier-specific code             | Supersedes the v0-only narrowing in ADR-004; verifier moves to a JSON wire protocol |
| ADR-009 | Wire-protocol backend; k4k ships no backend-specific code               | Supersedes the v0-only narrowing in ADR-003; symmetric to ADR-008                  |
| ADR-010 | Delegate concurrency to cotype · **SUPERSEDED→ADR-014**                | cotype removed; spec has one writer, agent proposes but never commits — no merge problem |
| ADR-011 | Autonomous-agent single-file UX · **SUPERSEDED→ADR-014**               | Daemon + concurrently-edited single file replaced by propose/review two-artifact UX; tier hierarchy survives (refined by ADR-016) |
| ADR-012 | Agent-driven toolchain selection · **REVISED→ADR-016 (deferred v1)**   | v1 pins one prover (Rocq+extraction); pluggability stands, autonomous per-project selection deferred |
| ADR-013 | Versions are git branches                                                | Each version lives on `k4k/version/<n>`; merges to default branch + tags `v<n>` on completion; `.k4k/version/<n>/` is audit-only |
| ADR-014 | Certification thesis + propose/review two-artifact UX (v3)              | Supersedes ADR-010/011; agent never commits the spec; certifier is a software engineer; cotype + in-file orchestration removed |
| ADR-015 | k4kspec — observational spec language                                    | Demotes ADR-005; spec denotes a relation R over observable I/O; frame/footprint fs; closed total value algebra; static stability; two-stage elaboration; pluggable artifact-class dimension |
| ADR-016 | v1 verification model + assurance refinements                           | Pin Rocq+extraction; defer toolchain self-selection; qualify "certified" + TCB manifest; executable spec-validation (clone-as-oracle); anti-vacuity; statement-preserving elaborator; under-spec sign-off; NFR triage; from the 2026-06-19 expert panel |
| ADR-017 | Guidance document (uncertified, best-effort, certificate-invariant)     | A third artifact for non-contractual desiderata (error wording, formatting, cosmetic NFRs); R is always the gate so guidance can never weaken the certificate; cosmetics-only, never safety |
| ADR-018 | **REALIZED** v1 certifying back-end (Rocq + extraction)                  | `k4kspec certify` works end-to-end: elaborate → coqc-checked proof → extract → binary + TCB manifest. All 6 v1-fragment specs certified, fresh-agent audited (tamper-tested non-vacuous). Audited-once `Kalgebra.v`. Honest limit: generated `run` matches spec ⇒ easy proofs |
| ADR-019 | **REALIZED + VALIDATED** agent proof backend (the central bet)           | Elaborator fixes `spec_rel`; external agent proposes `run`+proof; coqc is the only gate (+ retries, fresh-agent audited GREEN). `claude` closed: easy (`upper`+4 pinned), HARD inductive (`bsort` — invented insertion sort, proved Sorted/Permutation), and HARD non-sort (`partition` — custom preorder `part_le`, proof by construction). Relational-laws machinery added. Remaining ceiling: adversarial proofs (invented invariant / IH strengthening) |
| ADR-020 | Structured proof METHODOLOGY (skeleton-gate + fill)                     | One-shot monolithic generation stalls on multi-invariant proofs (`usort`). Replace with 4 phases: implement-naive → SKETCH (coqc-checks the lemma decomposition with the lemmas Admitted — the keystone) → fill each lemma in isolation (focused feedback) → assemble + final no-admits gate. Correctness-only for v1; naive→efficient deferred |
| ADR-021 | Compositional certification — scale impl, keep spec KISS                | The human signs ONLY the top observational `spec_rel` (stays flat). Implementation scales on two impl-side axes: compositional verification (`run` = composition of certified components, each a FUNCTIONAL Coq contract ∀x. S x (f x), agent-proposed + kernel-checked; ADR-020's skeleton gate generalizes to a module-interface gate) and naive→efficient refinement. Prototype: a 2-component `format ∘ core` certificate |
| ADR-022 | **REALIZED** v3 product surface — the PRD loop on the k4kspec core       | Files+CLI propose/review/sign/certify: three artifacts (spec, hints, `<name>.k4k/` ledger); BLAKE256 signatures = version history + under-spec acknowledgment + tier waivers (laws only, one choke point, certificate MUST disclose); certify gates on a valid signature (`--unsigned` = stamped dev run); retry-gated agent authoring with a monotonic decision journal; deterministic stubs make the loop agent-free-testable; Kalgebra embedded in the binary (works from any cwd) |

## How to add a new ADR

1. Pick the next free number: `adr-007-<topic>.md`.
2. Use the same frontmatter and section structure as the existing files.
3. Update this index with one line.
4. Cross-link from the relevant `kb/` files in the `related:` frontmatter.
