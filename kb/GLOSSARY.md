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

> **v3 note (2026-06-19).** ADR-014/015/016 reorient k4k to a certification tool. The **v3 terms** below are canonical. Terms under *"v2/earlier terms"* describe the prior single-file / cotype / two-run-formalization design and are retained for history. See `domain/prd.md` and the three ADRs.

## v3 terms (canonical — ADR-014/015/016)

### k4kspec
The dedicated, verifier-independent, software-engineer-readable **observational** specification language (ADR-015). The signed k4kspec document is **Artifact 1**, the certification anchor. An *elaborator* compiles it to a prover **statement** (never proofs).

### Observational spec
A specification phrased only in the program's *observable* vocabulary — argv, stdin, env, file-reads → stdout, stderr, exit code, file-writes — never in a prover's vocabulary. Avoids the model/reality gap.

### Spec relation (R)
The denotation of a k4kspec document: `R ⊆ Input × Output`, the set of *acceptable* outputs per input. Correctness theorem: `∀ i. R i (run i)`. In v3 the **desired characterization `D`** *is* the signed k4kspec and its elaboration to `R` (replacing the v2 "AST extracted by a formalization pass"). `S`, `Gap`, and `gap-step` are retained from the harness core.

### CASES / LAWS / EXAMPLES
The three k4kspec surface forms; their **conjunction** is `R`. CASES = guarded decision table on input (guards must be computable booleans; exhaustive ⇒ total). LAWS = relational ∀/∃ properties (may be arbitrary propositions). EXAMPLES = concrete rows, statically checked against the denotation.

### Frame / footprint
The declared set of paths a program may read/write (argv-parametric allowed, e.g. *reads file at argv[1]*). Everything outside the footprint is **framed** — provably unchanged — yielding a free "touches nothing else" property. Directory traversal/globbing is out-of-fragment in v1.

### Blessed value algebra
The closed, prover-realized library of **total**, byte-first primitives that k4kspec authors compose. No inline new primitives; `let` is abbreviation only. In the TCB (audited once per prover).

### Stability (v3)
A **static, deterministic** check on a k4kspec document (replaces the v2 two-run formalization): parses + type-checks + guards exhaustive + consistent (no input forced to an empty acceptable set) + examples agree + footprint in-fragment (ADR-015), plus the **anti-vacuity obligation** (ADR-016).

### Anti-vacuity obligation
Stability's dual: require a satisfiability witness and at least one **rejected** output per case (negative witness); dead guards and never-satisfied law-hypotheses are stability **errors**. Forbids a silently over-permissive `R`.

### Spec validation
Testing `R` against *intent* — compile k4kspec to an executable oracle and run differential/adversarial/property-based tests, surfacing counterexamples for the engineer to adjudicate — **before** any proof. Distinct from *verification* (does the impl satisfy `R`). The defense against autoformalization error.

### Elaborator
The trusted tool compiling k4kspec → a prover statement (never proofs), through a prover-independent IR. In the TCB; must be **statement-preserving** (emit adequacy evidence that the statement denotes the same `R` as the surface — ADR-016).

### Two-stage elaboration
Surface k4kspec → a prover-independent semantic **IR** (shaped by the class plugin) → a concrete prover. Classes × provers compose additively in code.

### Artifact class / class plugin
The pluggable dimension (like verifier and backend) supplying **P1** signature schema (operations, optional abstract state + invariants, trace shape), **P2** class vocabulary, **P3** semantic target + theorem template + coverage/example-discharge, **P4** I/O shim. v1 ships one plugin: `cli` (one-shot, no abstract state).

### I/O shim
The trusted real-world ↔ model bridge (plugin obligation P4), audited once per class×prover, **frame-enforcing**. Marshals real argv/stdin/env/footprint-files into `Input`, effects `Output`, and physically touches only the declared footprint.

### TCB manifest
The per-certificate list of every trusted component — Rocq kernel, extraction, OCaml runtime, blessed value algebra, I/O shim, elaborator — with versions and audit dates. **"Certified" is always qualified by it** (ADR-016).

### Propose/review
The interaction model (ADR-014): the agent *proposes* spec edits; the **human is the sole committer** of the spec. One writer per artifact; no concurrent-edit machinery.

### Certification anchor
The signed k4kspec document — the artifact the software engineer reviews and vouches for. Leg (a) of the trust argument.

### Spec-simplicity budget
The measured reviewability bound on a spec (size, case/law count, in-fragment footprint, blessed-vocabulary-only). Exceeding it trips a decompose-or-drop-tier response — KISS made an enforced gate, not an assumption.

### Guidance document
**Artifact 2** (ADR-017): a third, *uncertified*, human-owned document (working name `<project>.hints`; the user's "indications") holding non-contractual desiderata — error wording, formatting, cosmetic NFRs. Best-effort, edited via propose/review, frozen per spec version. Cosmetics only — never safety/security. The three artifacts are: signed k4kspec spec (certified), guidance document (uncertified), proof development (hidden).

### Certificate invariance
The property that makes the guidance document safe (ADR-017): `R` is *always* the verification gate, so guidance can never weaken or break the certificate — the worst a guidance entry can do is be ignored or surfaced as a `guidance ↔ R` conflict (spec always wins).

### Intent-seeded generation
The v3 entry point (ADR-014): the user states intent ("certified clone of GNU `cut`"); the agent *drafts* both the spec and the guidance document from domain knowledge, asking clarifying questions only at genuine ambiguities; the human reviews the decisions and signs. Principle #3 holds — the agent proposes (drafts), the human signs, the verifier proves.

### Clone-as-oracle (differential oracle)
When the intent is "certified clone of `Z`" and `Z` is runnable, `Z` is the differential oracle for the spec-validation phase (ADR-016 §11): k4k tests the generated spec against real `Z` and surfaces divergences before sign-off. The riskiest authoring case comes with the strongest validator.

### Under-specification sign-off
At sign-off k4k surfaces every deliberately-free observable dimension (e.g. unconstrained stderr prose) for explicit human acknowledgment (ADR-016 §12), distinguishing intended under-spec from a forgotten constraint. The certificate scope then discloses which channels are certified vs agent-authored/uncertified.

## v2/earlier terms

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
An external executable that, given a target source tree and a focus list of property IDs, writes a JSON result classifying each as `established | contradicted | unknown`. Per ADR-008+ADR-012, k4k ships **no** verifier itself — only the wire-protocol adapter `Verifier_external`. **The agent (running on a frontier model) chooses the toolchain per project and emits a wrapper script** (typically alongside the project source, e.g. `proofs/verify.sh`) that translates between the wire protocol and the native tool (`coqc`, `frama-c -wp`, `lean`, `verus`, …). v2 ships no reference verifier — only the protocol document at `external/verifier-protocol.md`. See ADR-012 for the rationale.

### Verifier adapter
The OCaml module inside `lib/` that satisfies `Verifier.S`. Per ADR-008, k4k ships exactly two: `Verifier_external` (the only production adapter — it spawns a configured executable per `external/verifier-protocol.md` and reads a JSON result) and `Verifier_stub` (test harness). Per-tool intelligence (alcotest output regexes, coqc exit-code interpretation, etc.) lives in the verifier executable itself, not in any k4k module.

### Gap-step
One iteration of the harness loop: pick the highest-risk property in `G`, ask the agent for a patch, apply directly to the working tree on the in-flight version branch, run the verifier, accept (commit `[k4k] establish <pid>`) or reject (`git reset --hard HEAD`). See `spec/algorithms.md#gap-step`. (Pre-v2 used a `k4k/gap/<id>/<ts>` scratch branch; that indirection is gone post v2-batch-4a.)

### Risk score
A deterministic function mapping a property to `[0, 1]`. Used to pick the next gap-step's target. No agent input. See `spec/algorithms.md#risk-score`.

### Owner (of a section or file)
**For the interaction file** (post-ADR-010): ownership is *positional* — k4k writes only sections whose H2 heading matches `## k4k:clarification:*`; everything else is user-authored. Concurrency is delegated to `cotype` (3-way merge); a user who edits a k4k-managed section surfaces as a `cotype save → conflict` outcome rather than an in-document ownership flip. **For target-KB files under `.k4k/`**: YAML frontmatter `owner: user | k4k` plus a `content_hash`; hash mismatch on read flips ownership to `user` for the run. See `spec/algorithms.md#ownership`, `external/cotype.md`, ADR-010.

### Version (v2)
A snapshot of the formal characterization `D` taken when the spec stabilizes. Each version lives on a git branch named `k4k/version/<n>` (per ADR-013); accepted gap-steps commit to the branch; on completion k4k merges to the user's default branch and tags `v<n>`. `.k4k/version/<n>/` carries audit-only metadata (no source). User edits during in-flight development queue for version *n+1* without disturbing version *n*.

### Verification tier (v2)
Per `domain/prd.md` and ADR-011, every property in a version is verified at one of three tiers:
- **Tier A** — full formal verification (Rocq+Extraction, Frama-C/ACSL+WP, Lean, Verus, F*, …). The default; k4k aims for this on every property.
- **Tier B** — formal model + intensive testing (property-based testing + fuzzing of an implementation against a formal model). Requires user sign-off.
- **Tier C** — testing only. Requires user sign-off and explicit acknowledgment that the formal-correctness goal is forfeited for the relevant property.

### Wrapper script (v2)
The shell script the agent emits alongside the project source that translates between the verifier wire protocol and the native toolchain (e.g. `proofs/verify.sh` invoking `coqc`). Per ADR-012, k4k ships no canonical wrapper; each project gets its own, generated by the agent for the chosen toolchain.

### Tradeoff proposal (v2)
A `## k4k:tradeoff:proposal:<ts>` section appended to the `.k4k` file when the agent could not establish a property at Tier A within the formalization budget. Contains: the affected property, why Tier A failed, the proposed degraded tier, what's lost, what's gained. The user replies inline with `Approved: Tier B` / `Rejected: <guidance>`. See ADR-011.

### cotype
**Removed in v3 (ADR-014).** k4k no longer depends on cotype: the spec has one writer (the human), the agent proposes but never commits, so there is no concurrent-edit problem to merge. Definition retained for history. — A small CLI (`pipx install cotype`) that provides safe-save concurrency on a single text file via 3-way merge over POSIX `diff3`. k4k delegates the user-agent interaction-file protocol to it (per ADR-010). Hardcoded runtime dependency, like `git`. Six commands: `init`, `open`, `save`, `status`, `resolve`, `cat-base`. The contract k4k depends on is in `external/cotype.md`.

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
