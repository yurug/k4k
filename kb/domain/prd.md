---
id: domain.prd
type: spec
summary: v3 product scope. k4k produces CERTIFIED POSIX-like programs from a human-signed, formal-but-readable specification (k4kspec). A software engineer reviews and signs a simple observational spec; k4k proves an implementation against it and ships a certificate with an explicit TCB. The agent proposes; the human commits.
domain: product
last-updated: 2026-06-19
depends-on: [glossary, adr-014, adr-015, adr-016]
refines: []
related: [spec.api-contracts, spec.algorithms, properties.functional, properties.non-functional]
---

# Product Requirements — k4k v3

## One-liner

**k4k turns a KISS program into a certified software component.** A software engineer writes and signs a *simple, formal-but-readable* specification (in **k4kspec**); k4k develops an implementation and a machine-checked proof that the implementation satisfies that spec, then ships a certificate naming exactly what is trusted. The engineer never writes Rocq, ACSL, or tactics — but they *do* read and vouch for the spec.

## The trust argument (why anyone should believe a k4k certificate)

Two legs, both required:

- **(a) Reviewable anchor.** The spec is simple enough that a competent software engineer — *not* a proof engineer — can read it and vouch that it says what they meant. This is what `k4kspec` (ADR-015) exists to make possible: an *observational* spec phrased only in the program's observable vocabulary (argv, stdin, env, file-reads → stdout, stderr, exit, file-writes), never in a prover's.
- **(b) Machine-checked link.** The implementation is mechanically proven to satisfy *that* spec, modulo an explicit, named **TCB** (ADR-016). "Certified" is always qualified by the certificate's TCB manifest.

If leg (a) fails, k4k will have flawlessly certified the wrong thing — so the spec is **validated** (tested against intent), not merely **verified against**.

## Persona

A competent **software engineer** on Linux/macOS who:
- can read a precise, declarative spec (decision tables, relational laws, examples) and judge whether it captures intent;
- does **not** know — and never needs to write — Rocq, ACSL, Lean, dune internals, or proof tactics;
- wants the resulting component *certified*, not merely running, and is willing to **review and sign** the spec and to adjudicate the agent's proposed spec edits.

(This corrects the v2 persona, which wrongly assumed a non-technical author who needs no formal-methods literacy at all.)

## What the engineer does (the UX)

The interaction is **propose/review with one writer per artifact** (ADR-014). There is no daemon editing a file under the user, and no concurrent-edit machinery.

1. **Author / co-author the spec.** The engineer writes a `k4kspec` document (or starts from a draft the agent proposes from a prose intent). The engineer is the **sole committer** of the spec — the certification anchor.
2. **Review proposals.** The agent never commits the spec; it *proposes* edits — resolve a contradiction, fill a gap, offer a formalization, flag an out-of-fragment construct. The engineer accepts or rejects each.
3. **Sign a spec version.** When the spec is *stable* (a static, deterministic check — ADR-015) and *non-vacuous* (anti-vacuity obligation — ADR-016) and *validated* (the executable-spec oracle agrees with the engineer's examples and surfaced counterexamples), the engineer signs it. The signature is the certification act.
4. **k4k develops autonomously** against the frozen, signed spec: it proves an implementation at **Tier A** and extracts a runnable binary. The engineer is not in this loop.
5. **Receive a certificate.** k4k delivers the implementation, the proof development, and a **TCB manifest** naming exactly what the certificate trusts.

## The two artifacts

- **Artifact 1 — the signed k4kspec spec.** Human-exposed, human-committed, the anchor. Nothing *observable* about the program's behavior is hidden from it.
- **Artifact 2 — the proof development.** Prover encoding, lemmas, tactics, implementation, extraction config. Agent-authored, hidden from the reviewer. What is hidden is *proof effort*, never *specification*.

## Verification tiers

| Tier | What it means | Sign-off |
|---|---|---|
| **A — Full formal verification** | Implementation machine-checked against the spec's elaboration (v1: Rocq proof + extraction to OCaml). Default and the goal. | Implicit — what k4k aims for on every property. |
| **B — Formal model + intensive testing** | A formal model exists; the implementation is conformance-tested (property-based + fuzzing) against it. | Required, in writing, with rationale. |
| **C — Testing only** | No formal artifact; tests only. | Required, with explicit acknowledgment that formal correctness is forfeited for the property. |

Tiers are **per-property**. v1 additionally extends the rigor knob to the *perimeter* (ADR-016): a certificate declares how its elaborator and I/O shim are assured (proof-producing vs property-tested-against-reference-semantics). "Tier A" therefore means *proven modulo the named TCB*, not unconditional certainty.

## v1 verification model (ADR-016)

- **One pinned prover: Rocq (Coq) + extraction to OCaml.** Agent toolchain self-selection is **deferred**; more provers arrive later as audited plugins. One auditable stack.
- **Extraction is named in every TCB manifest** as an unverified trusted step, and the **extracted binary is differentially tested** against the executable spec oracle.
- **Executable spec-vs-intent validation** runs *before* any proof: k4k compiles the spec to an oracle and tests `R` adversarially/differentially; counterexamples outside the engineer's examples are surfaced for adjudication.
- **Non-observable obligations** (secret-erasure, constant-time, resource bounds) are a per-certificate checklist the engineer must discharge or explicitly waive — the observational functional spec cannot state them.

## States the system can be in

- **Drafting / refining** — the engineer and the agent are converging the spec via propose/review; the spec is not yet stable, non-vacuous, and validated.
- **Signed** — the engineer has committed a spec version; the formal characterization `D` is frozen.
- **Developing** — k4k is proving version *N* autonomously against the frozen `D`. Spec edits the engineer makes meanwhile are a *new draft* for version *N+1*; they do not disturb the in-flight version.
- **Paused / blocked** — k4k hit an unknown-unknown (e.g. the signed spec is provably unsatisfiable in a way validation missed). It stops and *proposes* a spec change for the engineer to review.
- **Done** — version *N*'s gap is empty; all properties verified at their recorded tiers; certificate + TCB manifest delivered.

Rollback aborts an in-flight version and reverts to the previous completed version (per ADR-013, versions are git branches).

## User stories

- **S1 — First spec.** *I write a k4kspec for a CLI that uppercases its argv. k4k's validator runs my spec as an oracle, agrees with my examples, and surfaces one counterexample I hadn't considered (empty argv); it proposes a CASE to cover it, I accept and sign. k4k proves it in Rocq, extracts an OCaml binary, and hands me a certificate whose TCB manifest lists the Rocq kernel, extraction, the runtime, the value algebra, the shim, and the elaborator. The binary works.*
- **S2 — Proposal review.** *The agent notices my two examples contradict a law and proposes a spec edit naming the contradiction. I adjudicate (the law was wrong), accept the fix, re-sign.*
- **S3 — Trade-off.** *A property is too hard at Tier A within budget. k4k proposes Tier B with a written rationale; I sign off; it proceeds for that property only.*
- **S4 — Out-of-fragment.** *My spec needs to walk a directory tree. k4k's stability check flags it as out-of-fragment (spec-simplicity budget) and proposes a decomposition; I accept a narrower scope.*
- **S5 — Audit.** *A reviewer reproduces the proof: they read my signed k4kspec, run the prover over the proof development, check the TCB manifest, and re-run the differential tests of the extracted binary against the spec oracle.*

## Out of scope (v1)

- Artifact classes beyond `cli`: pure library, stateful ADT, server/daemon, UI are on the roadmap (ADR-015) but not built; UI needs a temporal/concurrency layer.
- Directory traversal / globbing / streaming-stdin / unbounded-env programs — out-of-fragment; they trip the spec-simplicity budget.
- Agent-selected toolchains and provers other than Rocq+extraction (deferred, ADR-016).
- GUI/TUI dashboards; multi-user/SaaS; non-Linux/macOS hosts; float-heavy numerics; ML.

## Success criteria

> **Realized status (2026-06-20, ADR-018).** The certifying back-end is built end-to-end:
> `k4kspec certify <file>` elaborates a spec to Rocq, coqc CHECKS the proof, extracts to OCaml,
> compiles with an I/O shim, runs, cross-checks vs the oracle, and writes a TCB manifest. All six
> v1-fragment example specs certify (upper/greet/grepf/kvget/cutf/catf), each independently
> fresh-agent audited with tamper tests (non-vacuous). This substantially meets criteria 1–2 *for
> the example fragment* — with the honest caveat that v1 generates `run` to match the spec (easy
> proofs); the agent proof backend (ADR-019, criterion 3-adjacent) and the propose/review intent
> UX remain.

1. A software engineer with no Rocq experience writes and signs a k4kspec for "echo with `--upper`", reviews k4k's proposed edits, and ends with: a working OCaml binary extracted from a Rocq proof, a proof development that re-checks, and a **TCB manifest** that honestly names every trusted component.
2. The same flow succeeds at Tier A on a more demanding in-fragment filter (e.g. `grep -F`-class).
3. A property genuinely too hard for Tier A reaches Tier B with written sign-off.
4. The executable spec-validation phase catches at least one injected wrong-but-well-formed spec before any proof is attempted (the autoformalization defense works).
5. All P-properties green; NF-properties within budget; the conformance suite runs cleanly.

## Constraints inherited from `kb/NOTES.md`

- **Deterministic** harness (same observable behavior ⇒ same evaluation) — now realized by k4kspec being the formal object, with stability a static check (ADR-015).
- **Efficient** — each agent-context update reduces the gap; *earned* by counterexample/diagnostic feedback and the incorrectness pre-gate (ADR-016).
- **Complete** — every observable aspect that matters is covered; under-specification is explicit, and the anti-vacuity obligation forbids a silently over-permissive spec.
- **Model-agnostic** — only the human and the verifier judge validity; the agent proposes, the harness accepts or rejects.

## Agent notes

> **The recursive nature is intentional.** We use a coding agent (Claude Code) to build a coding agent (k4k). The agentic-dev-kit methodology applies to building k4k itself; k4k embeds its own, more rigorous methodology for building target programs. `kb/` is the meta level; `.k4k/` is the object level.
>
> **The engineer reviews the spec, not the engine.** Surfacing prover choice, extraction, build commands, or git internals into the spec surface is a UX bug. But the certificate's **TCB manifest** must surface, honestly and in full, exactly what the certificate transitively trusts — that disclosure *is* part of the product.

## Related files

- `architecture/decisions/adr-014-certification-propose-review.md` — UX + two-artifact model
- `architecture/decisions/adr-015-k4kspec-language.md` — the spec language
- `architecture/decisions/adr-016-v1-verification-model.md` — pinned prover + assurance refinements
- `reports/expert-panel-2026-06-19.md` — the 10-expert review grounding the v3 refinements
- `spec/algorithms.md` — the harness algorithm (to be synced to the v3 surface)
- `properties/functional.md`, `properties/non-functional.md` — invariants this PRD implies
