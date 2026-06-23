---
id: reports.agent-certified-programming-learnings
type: report
summary: Learnings from building k4k's agent proof backend — getting an LLM to write CERTIFIED CLI programs (Rocq proofs, coqc the only gate). The arc from "certify a spec-shaped program" to agent-invented inductive proofs, a proof methodology, and compositional scaling. Written as raw material for a blog post.
domain: reports
last-updated: 2026-06-23
depends-on: [adr-018, adr-019, adr-020, adr-021]
related: [reports.expert-panel-2026-06-19, notes]
---

# Getting an LLM to write certified software — learnings

*Raw material for a blog post. The arc, the turning points, the surprises, and the honest caveats.
All claims below are backed by committed, coqc-checked artifacts (commit refs inline).*

## The thesis

k4k's bet: **KISS ⇒ a simple spec any software engineer can review ⇒ a certified component.** The
human signs one *observational* specification — `argv/stdin/files → stdout/stderr/exit`, a relation
`R` — and a deterministic harness closes the gap to a kernel-checked proof. The agent (an LLM) is
stochastic and *never trusted*; it only proposes. The Rocq kernel (`coqc`) is the sole judge.
Everything below is about making that actually work, and what we learned doing it.

Stack: a k4kspec surface spec → elaborated to a Rocq `spec_rel` → an implementation `run` + a proof
of `∀ i, spec_rel i (run i)` → extracted to OCaml → compiled into a real binary + a TCB manifest.

---

## The narrative arc (the turning points)

1. **"Certify a spec-shaped program" is not the goal.** v1 *generated* `run` to match the spec, so
   the proof was a triviality. It certified the *pipeline*, not real software. (ADR-018)
2. **The central bet: hand the proof to the agent.** Elaborator fixes the statement `spec_rel`; the
   agent proposes `run` + the proof; `coqc` is the only gate. It worked on the first try — and the
   agent's `run` was *genuinely different* from the spec. (ADR-019, `01ecdb8`)
3. **The first "4/4 success" was a trap.** Every example spec closed first-try — but they all
   *pinned the exact output*, so the proof was always a case-split. The hard problem was hiding.
4. **Relational laws expose the real problem.** Specs that *under-determine* the output via a law
   (sort: "a sorted permutation") force a genuine proof. The agent **invented insertion sort and
   proved `Sorted`/`Permutation` by induction**. (`bsort`, `2b44787`)
5. **Construction, not retrieval.** A spec over an *unfamiliar* relation (`partition` around a
   custom implication-preorder) — the agent reasoned it out, didn't recall it. (`partition`, `fa0a30b`)
6. **One-shot generation hits a wall.** A two-invariant spec (`usort` = strict-sort + set-equality)
   **stalled completely** — no candidate produced. The fix wasn't a bigger prompt.
7. **A methodology beats a bigger prompt.** Decompose → *kernel-check the plan* → fill. The same
   model then closed `usort`. (ADR-020, `6e9f3ae`)
8. **Scale without breaking KISS.** Real programs need modular architecture, but the human-signed
   surface must stay flat. Compositional certification: the agent proposes components with
   kernel-checked contracts; the human still signs one observational spec. (`grepf` as 5 components,
   ADR-021, `0b4364d`)

---

## Learnings

### Conceptual

**L1 — The proof is the easy leg; trust collapses onto the spec + the perimeter.** (The keystone
from a 10-expert panel review.) A kernel-checked proof is worth exactly what its *statement* and its
*TCB* are worth. So the entire design effort goes into: keeping the human-signed statement simple
and reviewable, and shrinking/being-honest-about the unverified perimeter (elaborator, I/O shim,
extraction, the blessed algebra). The proof itself is the part you can most trust.

**L2 — "Certify real software" vs "certify a spec-shaped program."** The dividing line is whether
the implementation is allowed to *differ* from the spec. When the harness generates `run` from the
spec, the proof is reflexivity and you've certified nothing interesting. The moment an *independent*
`run` must be proven equivalent, you have real software certification. On the very first agent run
(`upper`), the agent inverted the branch structure and chose its own error message — and proved it
equivalent. That difference *is* the result.

**L3 — Pinned outputs hide the hard problem (the most important surprise).** If a spec says
`stdout = <exact expression>`, then *any* correct implementation is forced to compute that
expression, and the proof collapses to a case-split. We got 4/4 "hard" specs closing first-try and
nearly declared victory — but they were all pinned. The genuinely hard proof only exists when the
spec **under-determines** the output via a *relational law* (sorted, partitioned, same-set). Lesson
for anyone benchmarking LLM proving: **check whether your spec actually leaves the implementation any
freedom.** If not, you're measuring case-splits.

**L4 — LLMs construct proofs over unfamiliar relations, not just retrieve known ones — but it's a
spectrum.** `bsort` (insertion-sort correctness) is a *textbook* proof; impressive that the model
adapts it to the exact `spec_rel`, but it's near the retrieval end. `partition` used a deliberately
weird relation `part_le a b := (b<109 → a<109)`; the model discovered it's a transitive total
preorder and found the **vacuous-truth argument** (the implication is trivially true when the
antecedent fails) and the right `Permutation_cons_app` lemma. That's construction. Designing the
*relation* to be non-canonical is how you push past retrieval.

**L5 — KISS pins the spec, not the code.** This is the answer to "won't real programs be too big to
certify?" The observational spec stays flat no matter how large the implementation grows. A
certified `grep` presents the human with *one* relation; the 5-module implementation behind it is the
kernel's problem. **Implementation size ↑, human-reviewed surface constant** — that's the property
to protect at every step.

**L6 — Naive-first is a scaling lever, not a limitation.** A "20kloc grep" is *C grep* — Boyer-Moore,
mmap, DFA caching: performance engineering. A grep built *for proof-simplicity* is a few kloc of
Rocq. You certify the simplest correct implementation; efficiency becomes a *separate*,
behavior-preserving certificate (`run_fast = run`) applied only where a benchmark demands it.
Correctness and speed are different certificates.

### Methodological

**L7 — The kernel can check the PLAN, not just the proof (the keystone idea).** `coqc` accepts a
proof skeleton whose helper lemmas are `Admitted`. So you can have the agent emit the lemma
*statements* + the top-level proof that *uses* them, and the kernel certifies — in seconds, against
stubs — that **the decomposition is type-correct and *sufficient to close the goal*, before any hard
lemma is proved.** This "skeleton gate" is the propose/accept-or-reject pattern lifted to *structure*.
It catches a misaimed decomposition cheaply and hands the agent a validated scaffold to fill. It
generalizes to a "module-interface gate" for whole components. This was the single highest-leverage
idea in the whole project.

**L8 — Methodology beats a bigger prompt.** `usort` stalled under one-shot generation — the model had
to invent a long multi-lemma development in a single pass. The *same model*, given a
decompose-then-fill structure, closed it (a ~10-lemma development: sort+dedup, strict-sortedness,
set-equality via injectivity). The lever was **process, not prompt size**. If your agent is failing
a hard reasoning task, the question is rarely "how do I prompt harder" and usually "what's the
checkable intermediate artifact."

**L9 — Decompose for tight feedback, not just for difficulty.** A coqc error from a 120-line monolith
is useless. The same error against a single 8-line lemma is actionable. Decomposition's payoff is as
much about **localizing the feedback loop** as about making the proof tractable.

### Engineering gotchas (the ones that actually cost time)

**L10 — A tool-enabled agent sabotages itself.** The biggest single blocker wasn't the math — it was
that `claude -p` had tool access, *tried to compile its own proof*, got blocked by permission
gating, and wrapped its answer in apologetic prose ("the compile is blocked by command-approval…").
That prose broke the harness's coqc input. The proof underneath was *correct* — it compiled when we
extracted it. **Run the generator tools-off** (`--allowedTools ""`); the agent's job is to produce
the artifact, the *harness's* job is to verify it. Don't let the prover-of-record try to be the
verifier.

**L11 — Latency masquerades as failure at the hard tier.** Monolithic generation of a long proof
repeatedly hit wall-clock timeouts with *no verdict* — which reads as "the model can't do it" but is
really "the model didn't finish typing." Several apparent failures (cutf, the first bsort, usort) were
latency. Smaller per-step generations (the methodology) help directly.

**L12 — A multi-step agent loop must stream progress.** Our structured backend accumulated its log and
printed it only on return — so a mid-run timeout showed *nothing*. Adding live per-phase logging to
stderr was essential to even *see* whether it was stuck or slow. Observability is not optional once
the harness makes many sequential model calls.

**L13 — "coqc is the only gate" means nothing until you try to game it.** A fresh adversarial auditor
attacked the gate: redefine `spec_rel` to `True` (→ coqc: `spec_rel already exists` — the elaborator's
statement is authoritative), `Admitted` (→ banned-word gate), bare `admit` (→ can never close `Qed`),
`Require Import Classical` to "prove" a false equation (→ still an incomplete proof). All blocked.
**The soundness claim is only as good as the adversarial audit behind it.** Also: a tamper test —
corrupt the extracted `run` and confirm coqc *rejects* — is what proves the statement is non-vacuous.

**L14 — Report what you actually checked.** For under-determined specs the binary's output is
proof-guaranteed but not oracle-comparable. The honest line is `binary MATCHES 7/9 (2
under-determined: proof-guaranteed, not cross-checked)` — never "MATCHES" over inputs you skipped.
Silent truncation reads as coverage you don't have.

### Meta

**L15 — Don't overfit the example.** Early on, an offhand "like cloning grep" pulled the whole build
toward grep-specific machinery. An example is one instance, not the spec of the work. Build the
general mechanism; let the example be a test of it.

**L16 — Fresh-agent adversarial audits + tamper tests are the unit of confidence.** Every milestone
was independently re-run by a throwaway agent that tried to break it. "It passed when I ran it" is
not evidence; "a skeptic who tried to defeat it reported GREEN, including a non-vacuity tamper test"
is.

**L17 — Pair every result with what it does NOT show.** Insertion-sort correctness is textbook;
grepf's five components have *trivial* proofs (breadth, not depth); breadth and depth haven't been
combined in one program yet. Stating the boundary with each win is what keeps the narrative honest —
and is usually where the next experiment comes from.

---

## Evidence table

| spec | what it demonstrated | result |
|---|---|---|
| `upper` | agent's `run` differs from spec (inverted branches, own error msg) + proof | closed, attempt 1 |
| `grepf/kvget/cutf/catf` | **pinned outputs ⇒ easy proofs** (the trap) | 4/4 first-try, but case-splits |
| `bsort` | invented insertion sort; proved `Sorted ∧ Permutation` by induction | closed (after tools-off fix) |
| `partition` | proof *construction* over an unfamiliar preorder (`part_le`) | closed, attempt 1 |
| `usort` | multi-invariant (strict-sort + set-equality); **one-shot stalled** | closed only via the methodology |
| `bsort` (compositional) | agent-driven 2-component decomposition | certified |
| `grepf` (compositional) | **first multi-module certificate — 5 agent-chosen components, 39/39** | certified |

Methodology (ADR-020): implement-naive → **skeleton gate** → fill → assemble. Compositional
(ADR-021): functional component contracts (`∀x. S x (f x)`), agent-proposed + kernel-checked;
**module-interface gate**; human signs only the top observational spec.

---

## Soundbites (quotable)

- "The agent is stochastic and never trusted. The kernel is the only judge."
- "Pinned outputs hide the hard problem — if the spec leaves no freedom, you're measuring case-splits."
- "We didn't need a bigger prompt. We needed the kernel to check the *plan*, not just the proof."
- "KISS pins the spec, not the code: the implementation became a five-module graph; the human still
  signs one relation."
- "The blocker wasn't the math — it was that the agent kept trying to compile its own proof."
- "Certify the simplest correct program; make it fast later, as a separate certificate."

---

## Honest open boundary (for a forward-looking ending)

What's validated: the agent proof backend (coqc-gated, adversarially audited); hard *inductive*
proofs (sort, custom-preorder partition); the structured methodology (unblocks multi-invariant
proofs); compositional *breadth* (a 5-module grep-class certificate). What's *not* yet shown: a
single target with **breadth + a deep component** (a grep-then-sort pipeline), recursive
decomposition (a hard component spawning its own sub-certification), a reusable certified-component
library, and the hardest proof tier (non-obvious invariants / IH strengthening the model must
invent). And the TCB is still real: every certificate is "proven *modulo* the Rocq kernel +
extraction + the OCaml compiler + the blessed algebra + the I/O shim + the elaborator" — shrinking
and honestly manifesting that perimeter is permanent work, not a footnote.
