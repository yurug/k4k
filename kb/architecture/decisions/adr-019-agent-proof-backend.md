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

Three tiers, all with `claude` as the backend (run **tools-off**, `--allowedTools ""`, so it emits
Coq instead of trying to compile it itself), the kernel as the only judge:

1. **Easy (pinned outputs).** `upper`: claude produced a `run` with **inverted branch structure**
   and **its own error message** — genuinely different from the spec — coqc accepted it on attempt 1.
   Then `grepf`/`kvget`/`cutf`/`catf` all closed first-try. *Caveat:* these specs pin the determined
   output to an exact expression, so any correct `run` is forced ≈ the spec and the proof is just
   case-split — the elaborator's generic tactic would close them too. Reliable, but not real proving.
2. **Hard (relational law → genuine induction).** `bsort` (stdout's bytes are a **sorted
   permutation** of `argv[0]` — under-determined; only a law constrains it): the deterministic path
   **fails** (nothing to copy), and claude **invented insertion sort and proved `Sorted` +
   `Permutation` by induction** (`insert_perm`/`isort_perm`/`HdRel_insert`/`insert_sorted`/
   `isort_sorted` + the `list_ascii_of_string` roundtrip lemma); coqc closed it on attempt 2
   (attempt 1's error fed back — the retry loop earning its keep). Binary sorts (`dcba → abcd`).
3. **Hard, non-sort (unfamiliar relation → proof *construction*).** `partition` (a permutation of
   `argv[0]` partitioned around `'m'`, expressed as `Sorted part_le` for the implication-preorder
   `part_le a b := b<109 → a<109` — deliberately *not* a stdlib order): claude closed it **on
   attempt 1** by genuine construction — `filter(<109)++filter(≥109)`, then `StronglySorted`, the
   **vacuous-truth** argument for `part_le` on the big group, `Permutation_cons_app` for
   partition-is-a-permutation, the roundtrip lemma. 0 escape hatches; binary `azbymc → abczym`.

- **The gate rejects non-proofs.** Wrong `run` + non-closing `Proof. reflexivity. Qed.` → coqc
  rejects → FAILED; `Admitted` → banned-word gate → FAILED; a `spec_rel` redefinition → coqc
  `spec_rel already exists` → FAILED (fresh-agent audited GREEN).

This is the moment v1 becomes *certify real software*: an agent-developed implementation, proven
equivalent to the human-fixed spec — including by **induction it constructs over relations it has
not seen** — with the kernel as judge.

## Relational-laws machinery (enables the hard cases)

A spec under-determines an output channel via a **law** (not a pinned expression): AST output-refs
(`OStdout`/`OStderr`/`OExit`) + a per-case `laws : expr list`; the elaborator conjoins the laws into
`spec_rel` and supports `P Any` (under-determined) channels; `Kalgebra` exports the law vocabulary
(`Sorted`/`Permutation`/`ascii_le`/`part_le`). For an under-determined channel the binary
cross-check is **skipped and honestly reported** (`N under-determined: proof-guaranteed`) — the
*proof*, not the oracle, is the guarantee there. (Two harness fixes were the real blockers, not
model capability: run the agent tools-off, and `clean` strips prose around unfenced Coq.)

## Honest limitations (do not overclaim)

- **Validated:** the easy (case-split) AND hard (inductive: sort, custom-preorder partition) tiers.
- **Still untested — the real ceiling:** *adversarial* proofs needing **non-obvious IH
  strengthening** or a **deep invariant the model must invent** (not adapt from a known shape).
  `partition`'s *shape* (filter + StronglySorted) is a known CS pattern even though the `part_le`
  reasoning was derived. Expect failures there; that is where proof-repair / richer proof-state
  feedback will matter.
- One success ≠ a guarantee; specs may need retries, decomposition, or fall back to a lower tier.

## Next

- **Adversarial-tier spec** — one whose proof is not a known pattern (needs an invented invariant);
  find the ceiling, then measure how far the retry loop + feedback close the gap.
- **Proof-repair + richer feedback** (Ringer): feed structured proof state, not just stderr; on a
  spec edit, repair the prior proof.
- **Per-property model dispatch** (round-4 E3): frontier model for the hard goal, smaller models
  for technical lemmas — token economy.
- Keep `spec_rel` fixed by the elaborator; the **statement-preservation** work (ADR-016 §5) makes
  *that* trustworthy — the remaining TCB item between the human signature and the proof.
