---
id: domain.prd
type: spec
summary: v2 product scope. k4k is an autonomous coding agent that builds fully verified POSIX-like programs from a user-edited interaction file. The user only writes free-form text in the file; k4k does everything else.
domain: product
last-updated: 2026-05-08
depends-on: [glossary]
refines: []
related: [spec.api-contracts, spec.algorithms, properties.functional, properties.non-functional, external.cotype]
---

# Product Requirements — k4k v2

## One-liner

**k4k is an autonomous agent that builds formally verified POSIX-like programs from a single user-edited file.** The user writes free-form prose describing what they want; k4k asks clarifying questions in-line, develops + verifies the program with full formal-verification tools when feasible, and documents any verification trade-offs back to the user for sign-off — all through the same `.k4k` file.

## What the user does (the entire UX)

The user does **one thing**: writes in a `.k4k` file via [cotype](https://pypi.org/project/cotype/). They never run flags, never populate tooling configuration, never select verifiers, never know what `dune` or `coqc` is. All communication with k4k flows through that file.

```
$ pipx install k4k cotype
$ k4k myproject.k4k     # one-shot launch; the agent runs autonomously thereafter
```

After that single launch the user only edits `myproject.k4k`. The file is the protocol.

## How k4k responds (everything else)

k4k watches the file. Its visible behavior to the user is entirely in-file:

1. **Refining the demand.** While the spec is *unstable* — the user's prose doesn't yet denote a clear theorem — k4k appends `## k4k:clarification:<ts>` blocks with concrete questions. The user answers in place. cotype handles concurrency. k4k re-evaluates stability each round.

2. **Versioning.** When the spec stabilizes, k4k snapshots a **version** (a frozen formal characterization `D`) and starts developing it in **full autonomy**. The version's identity is recorded in the file (a `## k4k:version:<n>` block) and in the harness state.

3. **Developing + verifying.** Default verification tier is **full formal verification**: implementation extracted from a Rocq development, or Frama-C-verified C, or analogous. k4k chooses the toolchain implied by the formal characterization and self-installs/configures it. Tier A is the goal on every property.

4. **Trade-off negotiation.** When Tier A is infeasible for a specific property, k4k pauses development and writes a `## k4k:tradeoff:proposal:<ts>` block: which property, why Tier A failed, what degraded tier is proposed (Tier B = formal model + intensive testing of the implementation against the model; Tier C = testing-only, forfeits formal correctness), what's lost. The user replies inline; k4k waits for sign-off before proceeding at the degraded tier.

5. **Status.** k4k continuously updates a `## k4k:status` block with the current version's progress (per-property statuses, ETA, current activity). The user can read this without interrupting development.

## States the system can be in

While the user is typing or refining the spec:
- **Unstable** — `## k4k:clarification:*` blocks are open; k4k waits for answers.

Once stable:
- **Developing** — k4k is autonomously building version *N*. User edits to user-owned sections of the file are noted but **do not interrupt** the in-flight version; they queue for version *N+1*.
- **Paused / unstable** — k4k discovered an unknown-unknown during development and could not proceed. It pauses, marks the file unstable with a fresh clarification block, and waits.
- **Awaiting trade-off sign-off** — Tier A failed on a property; k4k has proposed a degraded tier and waits for the user's reply.
- **Done** — version *N*'s gap is empty; all properties verified at the recorded tier. If the user has accumulated edits queued for version *N+1*, k4k re-runs stability and (if stable) starts version *N+1*.

The user can request **rollback** by writing `request: rollback` (or similar agreed-on directive — exact convention pinned in the v2 ADR) inside the `## k4k:status` block. k4k aborts the in-flight version and reverts.

## Verification tiers

| Tier | What it means | When it applies | Sign-off |
|---|---|---|---|
| **A — Full formal verification** | Implementation is *extracted from* or *machine-checked against* a formal artifact (Rocq+Extraction, Frama-C/ACSL+WP, Lean, Verus, F*…). The verifier runs `coqc` / `frama-c -wp` / etc. and maps theorem/contract statuses to property statuses. | **Default. The goal.** | Implicit — this is what k4k aims for on every property. |
| **B — Formal model + intensive testing** | A formal model exists (e.g. a Rocq specification of expected behavior); the implementation is hand-written in another language; conformance is established by property-based testing + fuzzing of the implementation against the model. | When Tier A is too hard for a specific property and k4k can construct a model. | Required, in-file, with k4k's written rationale. |
| **C — Testing-only** | No formal artifact at all. Tests + alcotest. | Last-resort for when Tier B is also infeasible. | Required, in-file, with explicit acknowledgment that the formal-correctness goal is forfeited for the relevant property. |

Tiers are **per-property**, not per-program. A program may have 12 properties of which 10 are Tier A and 2 dropped to Tier B; the file's `## k4k:status` block reflects that distribution.

## Users

A single developer (or domain-expert author) on Linux/macOS who:
- Writes prose to describe what they want a program to do.
- Wants the resulting program *certified*, not just running.
- Is willing to engage with k4k's clarification questions and trade-off proposals through the same file they're authoring.
- Does **not** need to know OCaml, Rocq, dune, Frama-C, alcotest, cotype, git internals, or any tooling specifics.

## User stories

### S1 — First spec
> *I write `myproject.k4k` describing a CLI that uppercases its arguments. I run `k4k myproject.k4k` once and never touch the shell again. k4k appends three clarifying questions to the file (about argument parsing edge cases). I answer them. k4k snapshots version 1, starts developing it in Rocq with extraction to OCaml, and updates a status block as it progresses. After ~10 minutes the status reads "version 1: done, 12/12 properties verified at Tier A". I run the resulting binary; it works.*

### S2 — Iterative refinement
> *I add a new acceptance example to my `.k4k` file describing whitespace handling. k4k notes the change but does not interrupt the in-flight version 1. After version 1 finishes, k4k re-runs stability against my new example, snapshots version 2, and develops it.*

### S3 — Trade-off negotiation
> *k4k cannot prove a complex termination property at Tier A within the formalization budget. It writes a `## k4k:tradeoff:proposal:<ts>` block: "Property `P_terminates_on_well_founded_input` cannot be proven in Rocq under the time budget; specifically, the proof requires an induction on a measure I cannot synthesize. Proposed Tier B: formalize the termination predicate as a Rocq specification, hand-write the OCaml implementation, and verify conformance against random inputs (10 000 iterations) plus a fuzzing campaign (1 hour). What's lost: a proof of universal termination; in exchange we gain confidence on the tested distribution." I read it, write `Approved: Tier B` in the block, and re-save. k4k resumes development under Tier B for that property.*

### S4 — Stuck
> *During development, k4k discovers that my spec is internally contradictory in a way the formalization pass didn't catch (e.g. two refusing examples imply mutually exclusive error behaviors). k4k pauses development, marks the file unstable with a fresh `## k4k:clarification:<ts>` block naming the contradiction, and waits. I edit the file to resolve the contradiction; k4k resumes.*

### S5 — Rollback
> *I realize half-way through version 2's development that my whitespace-handling example was wrong. I write `request: rollback` in the status block. k4k aborts version 2's development, reverts to the version-1 implementation, and re-runs stability — now treating my updated examples as version 3 input.*

### S6 — Audit
> *A reviewer asks me to demonstrate the program is correct. I show them the `.k4k` file (the spec), and the project's `.k4k/` directory (the formal artifacts: Rocq sources, extraction config, machine-checked proofs, manifest mapping each property to the proof witness). The audit reproduces by running `coqc` over the bundled `.v` files; every theorem closes. The trade-offs (if any) are recorded with the user's signed-off rationale.*

## Command surface (v2)

```
k4k <file.k4k>      Start watching <file.k4k>. The agent runs autonomously thereafter.
                    All further interaction is through the .k4k file.
```

That's it. No flags exposed to the user. The watcher process may accept `-v`/`-vv` for *operator* debugging (helping someone develop or fix k4k itself), but those are not part of the user UX.

Exit codes: `0` on graceful shutdown (signal received and watcher stopped cleanly); non-zero only if the watcher itself can't start (cotype not installed, file unreadable, etc.). The agent's *work outcomes* (stability, version completion, trade-off proposals) are reported in the file, not via exit codes.

## Verifiable artefacts

For any version *N* k4k completes, the user can audit:
- The `.k4k` file (the prose spec + the version block + the trade-off history).
- The `.k4k/` directory (operational state per ADR-006/007: formal characterization, gap properties, agent-runs, verifier-runs, manifest, JSONL log).
- The implementation source tree (e.g. Rocq `.v` files + extraction config + extracted OCaml).
- Re-running the verifier (`coqc <file.v>` etc.) reproduces every claimed theorem closure.

## Constraints inherited from `kb/NOTES.md`

- The harness is **deterministic** (same observable behavior ⇒ same evaluation), **efficient** (each evaluation modifies the agent context to *reduce* the gap), **complete** (every aspect that matters is covered).
- Verifiable artefacts: the `.k4k/` directory + the source tree are sufficient to reconstruct the state of any decision k4k made.
- Model-agnostic: no agent's *judgment* validates anything. The verifier (`coqc`, `frama-c`, etc.) and the human are the only judges.
- Class scope: POSIX-like CLIs and libraries with well-specified I/O whose behavior is fully determined by argv + filesystem.

## Out of scope

- GUI / TUI dashboards. The status block in the file is the only display surface.
- Multi-user / team / SaaS modes. Single-developer single-file.
- Programs whose behavior is not fully determined by argv + filesystem (interactive applications, distributed systems, GPU/numerics-with-floats, ML model training, …). Recognized as out-of-scope at first stability check; k4k declines to start a version for them.
- Hand-managed verification: the user does not write Rocq, ACSL, Lean, etc. directly — k4k generates the formal artifacts. (The user *can* edit them if they want; cotype handles the concurrency. But the default flow is fully synthetic.)
- Non-Linux / non-macOS hosts. Windows out.

## Success criteria

k4k v2 is considered complete when:
1. A user with no Rocq experience can write a free-form `.k4k` describing the canonical "echo with `--upper`" CLI, run `k4k <file>` once, answer the in-file clarifications, and end up with: (a) a working OCaml binary extracted from a Rocq development, (b) a `.k4k/` directory containing every artefact required to reproduce the proofs, (c) a status block reading `version 1: done, N/N properties verified at Tier A`.
2. The same flow on a more demanding program (e.g. a small filter — `cat` or `grep -F` — selected during the v2 plan) succeeds at Tier A.
3. A trade-off-requiring program (one property genuinely too hard for Tier A) reaches Tier B with appropriate user sign-off in the file.
4. All P-properties in `properties/functional.md` are tested green; all NF-properties are measured within budget; the conformance suite + drift-watch run cleanly.

## Agent notes

> **The recursive nature is intentional.** We are using a coding agent (Claude Code) to build a coding agent (k4k). The agentic-dev-kit methodology applies to building k4k itself; k4k embeds its own (smaller, more rigorous, formal-verification-grounded) methodology for building target programs. Don't conflate the two — `kb/` is for the meta level, `.k4k/` is for the object level.
>
> **The user does not see the engine.** Anything that surfaces tooling concepts (verifier choice, backend choice, budget caps, retention, file paths, build commands) to the user is a UX bug. Engine pluggability stays internal to `lib/`; the user's contract is the `.k4k` file shape, nothing more.

## Related files

- `external/cotype.md` — the runtime contract for the user-agent file protocol
- `spec/algorithms.md` — the harness algorithm (stability, formalization, gap-step, version transitions, trade-off negotiation)
- `spec/api-contracts.md` — the OCaml-internal interfaces (the public CLI contract is one row)
- `properties/functional.md` — P-invariants this PRD implies
- `architecture/overview.md` — module structure realizing the autonomous-watcher loop
- `architecture/decisions/` — ADRs capturing the architectural commitments (especially ADR-008/009/010, plus the forthcoming ADR-011 codifying the autonomous-agent UX + tier hierarchy)
