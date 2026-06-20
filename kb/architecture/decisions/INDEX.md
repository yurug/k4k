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

## How to add a new ADR

1. Pick the next free number: `adr-007-<topic>.md`.
2. Use the same frontmatter and section structure as the existing files.
3. Update this index with one line.
4. Cross-link from the relevant `kb/` files in the `related:` frontmatter.
