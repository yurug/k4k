---
id: adr-019
type: decision
summary: The agent proof backend (the central bet), realized. The elaborator fixes the certified statement spec_rel; an EXTERNAL agent proposes an implementation `run` (possibly different from the spec) plus a Coq proof of `forall i, spec_rel i (run i)`; coqc is the ONLY acceptance gate, with error-feedback retries. Demonstrated with claude closing a real proof; the gate rejects non-proofs. Realizes the two-artifact separation at the proof level.
domain: architecture
last-updated: 2026-06-20
depends-on: [adr-018, adr-009, adr-016, glossary]
refines: [adr-018]
related: [notes]
---

# ADR-019: The agent proof backend (realized)

## Status
Accepted / **realized** (2026-06-20). The "central remaining bet" named in ADR-018. Built in
`k4kspec/lib/agent_proof.ml` (+ `certify_v` refactor, `rocq_emit.emit_statement`), commit `01ecdb8`.

## Context

v1 (ADR-018) generated `run` to *match* the spec, so proofs were easy — it certified the
*pipeline*, not real software (the elaborator wrote both `spec_rel` and `run`, collapsing the
two-artifact separation). The bet: have an **agent develop an implementation** `run` that may
differ from the spec, and **prove** it satisfies the spec, with the prover as the only judge —
the harness's propose/accept-or-reject pattern (ADR-013, NOTES.md) lifted to the proof level.

## Decision

1. **The elaborator fixes the certified statement.** `Rocq_emit.emit_statement sp` emits the
   preamble (`Require Import Kalgebra`), the footprint-specialised `Input`, and `spec_rel` — and
   NOTHING ELSE. This is the certification anchor; the agent never writes it.
2. **The agent supplies only `run` + the proof.** The harness prompts an external agent for
   `Definition run : Input -> Output := …` and `Theorem correct : forall i, spec_rel i (run i).
   Proof. … Qed.`, assembles `statement ++ agent_body ++ extraction`, and runs coqc.
3. **coqc is the only acceptance gate**, plus the banned-word gate (no
   `Admitted/Axiom/admit/Parameter/Conjecture/Abort`). Accept iff coqc closes with `Qed` and no
   escape hatch. On failure, the coqc error is fed back into the prompt and the agent retries
   (bounded; default 4) — this is where the founding *efficiency* leg is earned (diagnostic
   feedback drives convergence), though convergence is not guaranteed.
4. **On success, the full downstream runs** (`Certify.certify_v`): extract → compile (+ I/O
   shim) → cross-check the binary vs the `Eval` oracle → TCB manifest.
5. **Pluggable backend** (ADR-009 philosophy): `$K4K_PROOF_CMD` is a command that reads the
   prompt on stdin and prints raw Coq on stdout (e.g. `cd /tmp && claude -p`); a deterministic
   stub (the elaborator's own `run`+proof) exercises the plumbing without an LLM.

## Soundness (why the agent cannot cheat)

- The agent supplies only `run` + proof **against the elaborator's fixed `spec_rel`**; it cannot
  weaken what is certified. If the agent tries to redefine `spec_rel`/`Input`, coqc raises a
  duplicate-definition error → reject.
- The certificate's strength is exactly the coqc kernel check of `correct` (modulo the ADR-018
  TCB). The agent's reasoning is *never* trusted — only its coqc-checked artifact.

## Demonstrated (2026-06-20)

- **claude closed a real proof.** `K4K_PROOF_CMD='cd /tmp && claude -p'` on `upper`: claude
  produced a `run` with **inverted branch structure** (`if len=1 then success else error`, vs the
  elaborator's `if len≠1 …`) and **its own minimal error message** (`"u"`, exercising the free
  `one_nonempty_line` stderr envelope) — genuinely different from the spec — and a proof that
  **coqc ACCEPTED on attempt 1**. The extracted binary matched the spec on 15 inputs.
- **The gate rejects non-proofs.** A wrong `run` + a non-closing `Proof. reflexivity. Qed.` →
  coqc exit 1 → rejected all attempts → `CERTIFY-AGENT: FAILED`. `Admitted` → banned-word gate →
  FAILED.

This is the moment v1 becomes *certify real software*: a differently-structured implementation,
proven equivalent to the human-fixed spec, with the kernel as judge.

## Honest limitations (do not overclaim)

- `upper` is the **easiest** spec (case-split + reflexivity/discriminate). Whether an LLM can
  close **harder** proofs — induction over `lines`/`filter`, or genuinely-optimised
  implementations needing real inductive arguments — is the **open empirical question**. The
  harness now makes it *measurable* (retry loop + diagnostic feedback) but does not answer it.
- One single-shot success ≠ general capability. Expect many specs to need retries, decomposition,
  proof-repair, or to fail within budget (then: trade-off to a lower tier, or human help).

## Next

- **Measure** the LLM proof-success rate across the fragment (grepf/kvget/cutf/catf) and harder
  hand-written specs; record it (panel's empirical-reviewability discipline, applied to proving).
- **Proof-repair + tactic libraries** (Ringer): on a spec edit, repair the prior proof; feed
  structured proof state, not just stderr.
- **Per-property model dispatch** (round-4 E3): a frontier model for the hard top-level proof,
  smaller models for technical lemmas — token economy.
- Keep `spec_rel` fixed by the elaborator (the statement-preservation work, ADR-016 §5, makes
  *that* trustworthy — the remaining TCB item between the human signature and the proof).
