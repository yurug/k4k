---
id: adr-017
type: decision
summary: Add a third artifact — the guidance document — for non-contractual, uncertified, best-effort desiderata (error wording, formatting, cosmetic NFRs). Human-owned (propose/review), excluded from the certificate and TCB, and certificate-invariant: R is always the verification gate, so guidance can never weaken or break the certificate.
domain: architecture
last-updated: 2026-06-20
depends-on: [glossary, adr-014, adr-016]
refines: [adr-014]
related: [adr-015]
---

# ADR-017: The guidance document (uncertified, best-effort, certificate-invariant)

## Status
Accepted (2026-06-20). Extends ADR-014's two-artifact model to **three, split by certification status**.

## Context

The relational spec `R` (ADR-015) deliberately under-specifies non-contractual outputs — error wording, formatting, the order of non-contractual output. Two positions existed for such a channel: **pin it** (exact bytes → certified, but rigid and verbose) or **leave it free** (`one nonempty line` / `any` → the agent's whim). Missing was a third lane: let the human *guide* the free part — and capture cosmetic non-functional desiderata (manpage, `--help` text, error phrasing) — **without** making any of it a certified contract, and without cluttering the certification anchor.

## Decision

1. **A third artifact: the guidance document** (working name `<project>.hints`; the user's term "indications"). Human-owned, edited via the same **propose/review** discipline as the spec (the agent proposes, the human commits). Optional, empty by default.
2. **It is uncertified.** Nothing in it is proven; it is excluded from the certificate's contract and from the TCB.
3. **Certificate invariance (the property that makes it safe).** `R` is *always* the verification gate; the implementation is checked against `R` regardless of guidance. Therefore the guidance document **can never weaken or break the certificate** — the worst a guidance entry can do is be *ignored* or *surfaced as a conflict*.
4. **Best-effort within `R`; conflicts surfaced; the spec always wins.** Concrete guidance is mechanically checked against `R`: if the indicated output is inside `R`'s free envelope → honor it; if outside `R` → surface the conflict and ignore it. Vague guidance is pure best-effort, the result still gated by `R`. **k4k does not prove guidance.**
5. **Cosmetics only — never safety/security.** Guidance must not carry safety, security, or contractual obligations (secret-erasure, constant-time, resource bounds). Those go to the certified spec or an explicit waiver (the NFR triage in ADR-016). k4k refuses to treat a guidance entry as discharging any obligation.
6. **No false reliance.** Guidance-governed behavior is uncertified and may change between versions. The certificate scope discloses this; downstream consumers must not depend on it (the generalized "don't parse stderr prose" rule).
7. **Promotion path.** A guidance entry you need to *rely* on is the signal to pin it into the certified spec.
8. **Per-version (recommended).** The guidance document is frozen alongside each signed spec version, so the audit trail shows what shaped `vN`'s binary. A single global doc is the alternative; revisit if per-version maintenance is burdensome.

## Consequences

- **The certified spec stays small and reviewable** — soft preferences move out of Artifact 1, protecting the simplicity budget and leg (a) of the trust argument.
- **The human gets a guided-but-uncertified lane** between "pin it" and "agent's whim."
- **"Certified" stays honest** — there is a crisp certified/trusted line, disclosed in the certificate scope.

## What this means for implementers

- `R` is the *only* verification gate. The guidance document is **development context plus a mechanical conflict check** — never a verification surface, never proven.
- Surface concrete `guidance ↔ R` conflicts at development time, with "spec wins" resolution.
- Disclose guidance in the certificate scope as uncertified and unstable.
- The three artifacts: **Artifact 1** = the signed k4kspec spec (certified); **Artifact 2** = the guidance document (uncertified, best-effort); **Artifact 3** = the proof development (hidden, agent-authored).
