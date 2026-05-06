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
An external executable that, given a prompt and a budget cap, returns text plus token usage (or refuses with `budget_exhausted` / `tool_error`). Per ADR-009, k4k ships **no** backend itself — only the wire-protocol adapter `Backend_external`. A reference backend for Claude Code lives at `examples/backends/claude-code/`. See `external/backend-protocol.md` for the contract; `architecture/decisions/adr-003-pluggable-backend.md` (partially superseded by ADR-009) for the original pluggability commitment.

### Coding agent / agent
Used interchangeably for an agent backend. Always headless (no interactive chat from k4k's perspective).

### Verifier
An external executable that, given a target source tree and a focus list of property IDs, writes a JSON result classifying each as `established | contradicted | unknown`. Per ADR-008, k4k ships **no** verifier itself — only the wire-protocol adapter `Verifier_external`. A reference verifier for OCaml + dune lives at `examples/verifiers/dune-ocaml/`. See `external/verifier-protocol.md` for the contract.

### Verifier adapter
The OCaml module inside `lib/` that satisfies `Verifier.S`. Per ADR-008, k4k ships exactly two: `Verifier_external` (the only production adapter — it spawns a configured executable per `external/verifier-protocol.md` and reads a JSON result) and `Verifier_stub` (test harness). Per-tool intelligence (alcotest output regexes, coqc exit-code interpretation, etc.) lives in the verifier executable itself, not in any k4k module.

### Gap-step
One iteration of the harness loop: pick the highest-risk property in `G`, ask the agent for a patch, apply on a scratch branch, run the verifier, accept or reject. See `spec/algorithms.md#gap-step`.

### Risk score
A deterministic function mapping a property to `[0, 1]`. Used to pick the next gap-step's target. No agent input. See `spec/algorithms.md#risk-score`.

### Owner (of a section or file)
**For the interaction file** (post-ADR-010): ownership is *positional* — k4k writes only sections whose H2 heading matches `## k4k:clarification:*`; everything else is user-authored. Concurrency is delegated to `cotype` (3-way merge); a user who edits a k4k-managed section surfaces as a `cotype save → conflict` outcome rather than an in-document ownership flip. **For target-KB files under `.k4k/`**: YAML frontmatter `owner: user | k4k` plus a `content_hash`; hash mismatch on read flips ownership to `user` for the run. See `spec/algorithms.md#ownership`, `external/cotype.md`, ADR-010.

### cotype
A small CLI (`pipx install cotype`) that provides safe-save concurrency on a single text file via 3-way merge over POSIX `diff3`. k4k delegates the user-agent interaction-file protocol to it (per ADR-010). Hardcoded runtime dependency, like `git`. Six commands: `init`, `open`, `save`, `status`, `resolve`, `cat-base`. The contract k4k depends on is in `external/cotype.md`.

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
