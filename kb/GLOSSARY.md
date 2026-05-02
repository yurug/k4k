---
id: glossary
type: glossary
summary: Canonical terms used throughout the k4k KB, in one place so cross-references are unambiguous.
domain: meta
last-updated: 2026-05-02
depends-on: []
refines: []
related: [domain.prd, spec.data-model, architecture.overview]
---

# Glossary

## One-liner

Every domain term used elsewhere in the KB is defined here, exactly once. If a term is used in more than one file with different meanings, that is a bug — fix it here, not by adding qualifiers downstream.

## Scope

Terms only. Mechanisms and contracts live in `spec/`. Decisions live in `architecture/decisions/`. This file is referenced by every other KB file and is intentionally short.

## Terms

### Interaction file
A user-authored file (extension `.k4k`) that captures the desired program's specification in Markdown + YAML frontmatter. Contains user-owned sections (immutable for k4k) and k4k-owned sections (machine-managed). The CLI invocation is `k4k <file.k4k>`. See `spec/config-and-formats.md` for the format.

### Desired characterization (D)
The formal AST extracted from an *interaction file* by the formalization pass. Stored at `.k4k/characterization/desired/spec.json`. The harness's reference for "what the program must do".

### Current characterization (S)
The formal AST that summarizes what the *current source code* actually establishes, computed from verifier output. Stored at `.k4k/characterization/current/spec.json`.

### Gap (G)
The set difference `D \ S`: properties present in D whose status is not `established` in S. Materialized as `.k4k/gap/properties.json`. Empty gap ⇒ done.

### Property
A named, atomic claim about program behavior. Schema: `{id, statement, status, evidence, risk-score}`. `status ∈ {required, established, contradicted, unknown}`. See `spec/data-model.md`.

### Stable / unstable
An interaction file is **stable** iff (a) all required user-owned sections per the *program class* are present and non-empty, (b) the formalization pass produces at least one valid translation and all valid translations are semantically equivalent under canonicalization, (c) every aspect on the class's *coverage checklist* is covered. Otherwise **unstable**, and k4k blocks. See `spec/algorithms.md#stability`.

### Formalization pass
The deterministic procedure that translates an interaction file into a canonical AST (`D`). Calls the agent backend; canonicalizes the result; checks ambiguity by re-running and comparing. Pass/fail, never graded. See `spec/algorithms.md#formalization`.

### Coverage checklist
A class-keyed list of aspects that an interaction file must mention non-trivially to be stable. v0 ships only the `cli` checklist. See `spec/data-model.md#coverage-checklists`.

### Program class
The kind of program k4k is being asked to build, declared by the user in the interaction file's YAML frontmatter (`class: cli`). v0 supports `cli` only; future classes (`library`, `filter`, …) are deferred.

### Agent backend
A pluggable provider of headless coding-agent calls. v0 ships `claude-code`. The interface is defined in `spec/api-contracts.md#agent-backend` and the design rationale (including local-LLM support via Ollama) in `architecture/decisions/adr-003-pluggable-backend.md`.

### Coding agent / agent
Used interchangeably for an agent backend. Always headless (no interactive chat from k4k's perspective).

### Verifier
A pluggable provider of property-status verdicts. v0 ships `dune-ocaml` (typecheck + test suite). The interface is in `spec/api-contracts.md#verifier`. See ADR-004 for the extension point.

### Verifier adapter
A small module that maps a specific verifier's stdout/stderr/exit-code into our property-status enum. Naming: `Verifier_<tool>` (e.g. `Verifier_dune_ocaml`).

### Gap-step
One iteration of the harness loop: pick the highest-risk property in `G`, ask the agent for a patch, apply on a scratch branch, run the verifier, accept or reject. See `spec/algorithms.md#gap-step`.

### Risk score
A deterministic function mapping a property to `[0, 1]`. Used to pick the next gap-step's target. No agent input. See `spec/algorithms.md#risk-score`.

### Owner (of a section or file)
Either `user` or `k4k`. User-owned regions are inviolable — k4k never writes to them. k4k-owned regions are machine-managed; the user *may* hand-edit, in which case ownership flips to `user` (detected via content hash mismatch). See `spec/algorithms.md#ownership`.

### KB (knowledge base)
Used in two senses, never conflate:
- **k4k KB** — the directory `kb/` in the k4k repository. Describes k4k itself.
- **Target KB** — the directory `.k4k/` in a target project. Describes the program k4k is building, generated and maintained by k4k.
Both follow the agentic-dev-kit layout (per ADR-006).

### Canonical AST
The result of applying the canonicalization function to a raw AST: sorted fields, normalized identifiers (deterministic naming keyed on user section ids), stable order. The harness's determinism contract holds on canonical ASTs. See ADR-005.

### Acceptance example
A `(input, expected output)` pair the program must satisfy. ≥3 required per interaction file (per `cli` coverage checklist).

### Refusing example
A `(input, expected error)` pair. ≥1 required, exercises the error taxonomy.

### Convergence
Reaching `G = ∅` for the current `D`. Not guaranteed in finite time; k4k promises *non-regression* (no established property regresses without `D` changing) and *bounded responsiveness* (Ctrl-C honored within ≤5 s).

### Non-regression
The invariant that an established property cannot become un-established by k4k's actions alone. A user-driven `D` change can demote properties; k4k actions cannot.

### Budget unit
The unit in which agent-call cost is metered. v0 uses tokens-equivalent. Hard cap 1000 / invocation; soft cap 100 / gap-step. See `spec/config-and-formats.md`.

### Manifest
`.k4k/manifest.json`: the source-of-truth map for what's in `.k4k/`, including content hashes, last-stable timestamp, KB-file→source-fact map (used for incremental KB regeneration). See `spec/data-model.md#manifest`.

### Headless mode
Agent invocation that returns a single response without interactive turn-taking from k4k's side. For `claude-code`, the `claude -p <prompt>` form. The agent itself may take many internal turns; k4k sees one input, one output.

### Context economy
The discipline of fitting each agent call into the smallest possible prompt that still yields a correct answer, on the assumption that the agent may be a small local Ollama model. Codified in `conventions/context-economy.md`.

## Agent notes

> If you encounter a term not in this glossary, **stop and add it here first** before using it in another file. Glossary drift is the most common cause of KB rot.

## Related files

- `spec/data-model.md` — full schemas for the types named above (Property, AST, Manifest, …)
- `spec/algorithms.md` — the procedures named above (formalization, gap-step, canonicalization)
- `architecture/overview.md` — how the modules implementing these terms are wired together
- `architecture/decisions/` — ADRs that justify key choices
