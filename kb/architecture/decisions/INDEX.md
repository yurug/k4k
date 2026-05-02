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
| ADR-005 | Determinism on canonical AST; two-run formalization                    | Resolves the agent-stochasticity / harness-determinism tension        |
| ADR-006 | Two-layer KB — meta (`kb/`) and target (`.k4k/`)                       | Pins down round-2 user-edit on KB layout                              |
| ADR-007 | Deterministic in-process kb-regen for v0                                | v0 deviates from `algorithms.md#kb-regen`'s agent-driven model        |
| ADR-008 | Wire-protocol verifier; k4k ships no verifier-specific code             | Supersedes the v0-only narrowing in ADR-004; verifier moves to a JSON wire protocol |

## How to add a new ADR

1. Pick the next free number: `adr-007-<topic>.md`.
2. Use the same frontmatter and section structure as the existing files.
3. Update this index with one line.
4. Cross-link from the relevant `kb/` files in the `related:` frontmatter.
