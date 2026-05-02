---
id: indexes.by-task
type: index
summary: Routing table by task — given my current task, what do I load, in what order, what questions does this stack answer?
domain: indexes
last-updated: 2026-05-02
depends-on: []
refines: []
related: [INDEX]
---

# By Task — Routing Table

## How to use this file

Pick the task you are about to do. Load the listed files in order. Each task's *Key questions answered* lists the questions a contributor should be able to answer after reading the stack — if you can't, you missed a file.

Tasks are short. Long tasks are signs of misdrawn boundaries — split them.

---

## #implement — adding or modifying a k4k feature

**Load (in order):**
1. `INDEX.md`
2. `GLOSSARY.md`
3. `domain/prd.md` — confirm the change is in scope for v0
4. `kb/plan.md` (created in Phase 3) — find your step
5. `spec/algorithms.md` + the relevant section of `spec/data-model.md`, `spec/config-and-formats.md`, `spec/api-contracts.md`
6. `properties/functional.md` — find the P-IDs your function must enforce
7. `architecture/overview.md` — confirm the module seam
8. `conventions/code-style.md`, `conventions/error-handling.md`
9. `external/<sdk>.md` if calling an external dep

**Key questions answered:**
- Which property IDs does my new code enforce, and where is each tested?
- Which module does this belong in? (or does a new module need an ADR?)
- What is the input/output type? Are the ID/path types `private`?
- Which errors can this function raise? Are they all in `spec/error-taxonomy.md`?
- If I touch an external dep, is the request budget still within the cap?

**Exit criterion:**
Tests green; comment ratio ≥ 30% (no padding); `@invariant P<n>` on every public function that enforces a property.

---

## #audit — Phase-5 quality audit

**Load:**
1. `runbooks/audit-checklist.md` — the canonical checklist
2. `properties/INDEX.md` — what's expected to be enforced
3. `conventions/error-handling.md`, `conventions/testing-strategy.md`
4. `architecture/overview.md`
5. `spec/algorithms.md` (just to know what behaviors are claimed)

**Key questions answered:**
- For each axis: what specifically must I check?
- What counts as critical vs. high?
- Where do findings go?

**Exit criterion:**
0 criticals after iteration (Ralph Loop, max 5).

---

## #debug — diagnosing a behavior issue

**Load:**
1. `GLOSSARY.md`
2. `spec/error-taxonomy.md` — find the exit code first
3. `spec/algorithms.md` — locate the relevant procedure
4. `spec/config-and-formats.md` — what state should disk look like?
5. `properties/edge-cases.md` — match the symptoms against T-entries
6. The relevant `external/<sdk>.md` if calling out

**Key questions answered:**
- What error code did the user see, and what does the catalog say it means?
- Which step in `algorithms.md` could plausibly emit that error?
- Is the user hitting an edge case in `T*`?
- What does `.k4k/log.jsonl` reveal? Is the manifest consistent?

**Exit criterion:**
Repro reproducible from `.k4k/` + `<file.k4k>` alone; root cause cited from a spec/property file.

---

## #test — writing or fixing tests

**Load:**
1. `conventions/testing-strategy.md`
2. `properties/INDEX.md` — find the IDs your tests must reference
3. `spec/api-contracts.md` — if mocking, the contract you must satisfy
4. `external/verifier-protocol.md` — for the protocol your verifier executable must satisfy (test-name conventions are per-verifier, not k4k-wide)

**Key questions answered:**
- What's the test naming convention?
- Do I need property-based tests? Edge-case tests? Integration tests?
- Which stub do I use for the agent / verifier?
- What does ≥ 3 tests per file look like in practice?

**Exit criterion:**
Every P/NF/T-id in scope is referenced by ≥ 1 test name.

---

## #extend-backend — adding an agent backend (e.g. Ollama)

**Load:**
1. `architecture/decisions/adr-003-pluggable-backend.md`
2. `spec/api-contracts.md#agent-backend`
3. `external/<your-backend>.md` — write this first if it doesn't exist
4. `conventions/context-economy.md` — non-negotiable
5. `properties/non-functional.md#NF8`

**Key questions answered:**
- What does the `Agent_backend` signature require?
- Does my backend's failure model fit `EAGENT_UNAVAILABLE`?
- Does it satisfy NF8 (works under weakness profile)?
- Where is the new `.opam` dependency declared?

**Exit criterion:**
The full integration test suite passes against `Backend_<your-backend>` substituted at the DI seam.

---

## #extend-verifier — adding a verifier (e.g. Rocq, Frama-C, AFL)

**Adding a verifier requires zero changes to k4k's source** (per ADR-008). Build a standalone executable conforming to the wire protocol; users plug it in via the interaction file's `k4k.verifier.command` frontmatter.

**Load:**
1. `architecture/decisions/adr-008-verifier-protocol.md` — why no k4k code change
2. `external/verifier-protocol.md` — the wire contract (CLI shape + JSON result schema + exit codes)
3. `examples/verifiers/dune-ocaml/README.md` — worked example to copy from
4. `properties/non-functional.md#NF6` — the determinism contract your verifier must satisfy

**Key questions answered:**
- What CLI shape do I implement? (`--workdir`, `--focus`, `--output`)
- What JSON schema does the result file follow? (`by_property`, `raw_exit_code`, `duration_ms`, `warnings`)
- Which exit codes do I use? (0 = result written; 1/130/other = `Tool_error`)
- How do I name proof obligations / tests / theorems so my verifier maps them to property IDs? (`P<id>_<slug>` is the convention shared by reference verifiers; your verifier defines its own and documents it.)

**Exit criterion:**
Your executable runs against the protocol's compliance checklist (a small test fixture in `examples/verifiers/dune-ocaml/test/` exercises every contract clause; copy and adapt it).

---

## #write-prompt — authoring or modifying an agent prompt

**Load:**
1. `conventions/context-economy.md` — the rules
2. `external/ollama.md` — the capability target
3. `spec/algorithms.md` — what step does this prompt implement?
4. `properties/functional.md` — does the prompt help enforce a P-id?

**Key questions answered:**
- Within R1's token budget?
- Output schema flat per R2?
- One task per R3?
- Any "Claude-only smell" remaining?

**Exit criterion:**
`Backend_stub`'s weakness profile passes the test that exercises this prompt.

---

## #release — preparing a release

**Load:**
1. `domain/prd.md#success-criteria`
2. `runbooks/audit-checklist.md`
3. `properties/INDEX.md`
4. `kb/plan.md` (Phase 3)

**Key questions answered:**
- Are all v0 success criteria green?
- Is the audit at 0 criticals?
- Is the KB in sync with the code (Phase 6 done)?

**Exit criterion:**
A reproducible toy run from a fresh checkout produces `done` with the expected program.

---

## Agent notes

> **No browsing.** This file is the navigation layer. If you find yourself opening folder listings to find a file, the index has a gap — fix it here, then continue.

## Related files

- `INDEX.md` — master entry point
- All linked files above
