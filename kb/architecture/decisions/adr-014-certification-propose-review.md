---
id: adr-014
type: decision
summary: Reorient k4k to an explicit certification tool with a propose/review, one-writer-per-artifact UX and a two-artifact model (human-signed readable spec + hidden proof development). Supersedes ADR-010 (cotype) and ADR-011 (autonomous single-file UX).
domain: architecture
last-updated: 2026-06-19
depends-on: [glossary, domain.prd]
refines: [adr-011]
related: [adr-015, adr-016, adr-013]
---

# ADR-014: Certification thesis + propose/review two-artifact UX (v3)

## Status
Accepted (2026-06-19). **Supersedes ADR-010** (cotype delegation) and **ADR-011** (autonomous-agent single-file UX). Re-grounds the product framing established in v2.

## Context

Revisiting the core proposition (2026-06-19) reaffirmed and sharpened k4k's purpose: **k4k exists to produce *certified* software components.** The value chain is

> a KISS program ⇒ a *simple specification any software engineer can review* ⇒ together with a machine-checked proof, a **certified component.**

Trust rests on **two legs**: (a) the spec is simple enough that an engineer can read and vouch for it; (b) the implementation is machine-proven to satisfy *that* spec.

The v2 UX (ADR-011) ran k4k as an always-on daemon editing a single `.k4k` file concurrently with the user, with `cotype` (ADR-010) providing 3-way-merge concurrency. Two problems surfaced:

1. **The single file conflates three streams** with different owners and cadences — the spec (slow, human), the dialogue (turn-based, both), the telemetry (frequent, agent, read-only). The telemetry stream alone guarantees write contention; cotype exists to paper over a conflation we created.
2. **For a certification tool the conflation is fatal, not cosmetic.** If the agent can silently write the certification anchor (the spec), leg (a) is void — what gets proven is no longer what the engineer reviewed and signed; it drifted out from under the signature.

## Decision

1. **Co-authorship via propose/review, one writer per artifact.** The agent **never commits** to the canonical spec. It *proposes* edits (resolve a contradiction, fill a gap, offer a formalization); the human accepts or rejects. The human is the sole committer of the certification anchor. This mirrors the engine one layer down: gap-steps are diffs the harness accepts (commit) or rejects (`git reset --hard`), per ADR-013.
2. **Two artifacts.** (1) The human-exposed, human-signed *formal-but-readable* spec — the certification anchor, written in **k4kspec** (ADR-015). (2) The hidden proof development — prover encoding, lemmas, tactics, implementation, extraction. **Nothing observable is hidden from the certifier**; what is hidden is *proof effort*, never *specification*.
3. **cotype is removed.** Concurrency is *designed out* (one writer per artifact), not *merged away*. ADR-010 is superseded; `lib/cotype*`, `lib/clarification` cotype paths, and the cotype runtime dependency go.
4. **The always-on daemon + in-file status/clarification/tradeoff splicing is dropped.** Interaction is a review cycle: the agent proposes, the human reviews/commits; once a spec version is signed, the agent develops autonomously against the *frozen, signed* spec. ADR-011 §C machinery (much of `inline_blocks`, `status_splice`, `watcher_prune`, the P22 `version_user_edits` queueing) is superseded — it existed only to manage two writers on one file.
5. **The persona is a software engineer.** The certifier is a competent SWE reviewing a *simple* spec — **not** a proof engineer, but also **not** the non-technical author the v2 PRD imagined. The PRD's "needs no Rocq/OCaml/git" persona is wrong and is revised.

## Consequences

**Kept (sound, reused):** the harness core — gap-step propose/accept-or-reject, the verifier/backend wire protocols (ADR-008/009), branch-per-version (ADR-013), extraction.

**Superseded:** the cotype layer (ADR-010); the autonomous-daemon single-file UX and its in-file orchestration (ADR-011); the prose→formal *two-run formalization* as the stability mechanism (ADR-005's role — see ADR-015, where stability becomes a static check on k4kspec).

**Net:** rebuild the *surface* around the kept *harness core*. A meaningful slice of the v2 module set is now off-thesis; none of the load-bearing harness is.

## What this means for implementers

- The canonical spec has exactly **one writer** (the human). Every agent contribution to the spec is a *proposal* in a separate channel the human disposes of.
- Do not re-introduce cotype, the status-splice loop, or any concurrent-edit mechanism on the spec. If you find yourself needing a merge, you have two writers on one artifact — that is the bug.
- See **ADR-015** for the spec language and **ADR-016** for the v1 verification model and the assurance refinements.

## Panel grounding

The 10-expert verification panel (`kb/reports/expert-panel-2026-06-19.md`) unanimously affirmed the certification thesis and the spec-as-anchor, while flagging that the design *under-defends* the anchor. Those refinements are mechanized in ADR-016.
