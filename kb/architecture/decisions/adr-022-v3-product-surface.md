---
id: adr-022
type: decision
summary: The v3 product surface, realized on the k4kspec core — the full PRD loop as files + plain CLI. Three artifacts (spec, hints, <name>.k4k/ ledger); signatures pin exact spec bytes (BLAKE256) and are the version history; certify gates on a valid signature; tier waivers (laws only) weaken spec_rel at ONE choke point and the certificate MUST disclose them; propose/revise/propose-fix are retry-gated agent drafts with a monotonic decision journal; deterministic stubs make the whole loop agent-free-testable. The v2 watcher tree is superseded and untouched, pending retirement.
domain: architecture
last-updated: 2026-07-10
depends-on: [adr-014, adr-015, adr-016, adr-017, adr-018, adr-019, adr-021]
refines: [adr-014]
related: [adr-013]
---

# ADR-022: The v3 product surface — the PRD loop on the k4kspec core

## Status
Accepted / **realized** (2026-07-10, commits `271990d..`). Fills every product-surface gap the
KB left open (proposal channel shape, artifact layout, manifest/signature schema, waiver
semantics, decision-review format). Built entirely in `k4kspec/` (stdlib-only); the v2 watcher
tree is superseded (ADR-014) and untouched — retirement is its own later pass.

## Artifacts (per spec `greet`)
Ownership is **directory-shaped**: top level = human-owned, `greet.k4k/` = tool-owned ledger.
```
greet.k4kspec            the spec — human is SOLE writer (propose may CREATE it once)
greet.hints              guidance (ADR-017) — human-owned, optional, cosmetic only
greet.k4kspec.new        convenience copy of the latest proposal (mv = the acceptance act)
greet.k4k/
  decisions.md           D-numbered decision journal (agent-authored review input)
  proposals/<ts>-<kind>.md   every proposal ever (new|revise|fix); never auto-applied
  signatures/v<N>.sig    the version history == the sign-off records
  certificates/v<N>/     promoted deliverables: certificate.md, .v, _ext.ml, _main.ml, binary, tcb.md
  last-failure.md        honest per-lemma report of the last failed certify run
```
Cross-references use basenames (the triple is `git mv`-able). The tool never runs git; the
`.sig` chain (`previous: vN <hash>`) gives tamper-evident lineage (ADR-013 remains an
outer-harness concern, not a k4kspec one).

## Formats
One machine-record format (`lib/record.ml`): folded `key: value` header + `== section ==`
verbatim bodies; used by signatures and proposals. Hash = **`Digest.BLAKE256`** (OCaml stdlib)
over exact file bytes. Decision entries (`lib/decisions.ml`) are **monotonic and immortal** —
revise may only append and flip `[active]` → `[superseded-by:Dk]`; `check_monotone` rejects
rewritten history naming the exact entry and field.

## Signing and the gate
`sign` requires: parse + full check pass; **every under-specified dimension acknowledged**
(`--ack-underspec`, exit 4 otherwise — ADR-016 §12 as a recorded CLI act); waiver refs
validated. Any byte change invalidates (re-sign = v+1, chained). `certify`/`certify-agent`
on FILES **refuse without a valid signature** (exit 3); `--unsigned` and built-ins are
development runs — the TCB manifest is stamped
`Signature: none — development run, NOT a certified deliverable`, and nothing is promoted.
Successful signed runs promote artifacts + the certificate document into `certificates/v<N>/`.

## Tier waivers (v1-honest)
Waivable: **laws only** (`case#i.law#j:B|C` + mandatory rationale, recorded in the signature —
a waiver is a signed act, PRD S3). Pinned channels are never waivable (edit the spec + go
through the under-spec acknowledgment instead). `Sign.apply_waivers` is the **single choke
point**: waived laws are stripped from the spec value before elaboration in all three certify
modes; `check` always sees the full file (a fully-waived spec would fail check as vacuous —
by design, check never reads signatures). v1 has **no tier-B/C execution**: the certificate
states the waived law is NOT formally verified, that NO property testing was run, and quotes
the rationale verbatim. The Waivers section derives from the same signature record that drove
the weakening, so disclosure cannot diverge from what was weakened.

## Certificate (certificates/v<N>/certificate.md)
Computed, never prose: a per-case/per-channel scope table (`CERTIFIED (pinned)` /
`CERTIFIED-BY-LAW (n law(s))` / `FREE — uncertified`, sign-off-referenced / `NOT VERIFIED +
WAIVED`), the Waivers section, the TCB manifest verbatim (incl. the agent-provenance line),
and Not-covered (guidance per ADR-017; non-observable obligations named as neither checked
nor waived).

## Authoring (propose / revise / propose-fix)
`$K4K_AGENT_CMD` (prompt on stdin → text on stdout, same wire shape as `$K4K_PROOF_CMD`);
**deterministic stubs when unset** — the entire loop is agent-free-testable. Output contract:
tagged fenced blocks (```k4kspec / ```hints / ```decisions / ```summary), retry-gated
(structure → parse → check → decisions-monotone; error fed back verbatim; max 4; nothing
written until the gates pass). The prompt is `k4kspec_blurb`: the whole language in one
screenful + `grepf.k4kspec` as the single few-shot + the ADR-017 split rule (contractual →
spec; cosmetic → hints; never safety in hints). `revise` output = agent summary + a
**mechanical delta** (computed by parsing both specs) + a line diff + the draft's check
report + a signature-invalidation warning. `propose-fix` requires the last-failure report (written
automatically by failed certify runs) and drafts a provability-restoring spec change.

## The laws surface (prerequisite, same pass)
`law <expr>` is a case statement; `stdout`/`stderr`/`exit` are expressions **only inside
laws** (static post-parse check). The four law-carrying built-ins now exist as surface files
whose emitted `spec_rel` is byte-identical to the AST built-ins'. Kalgebra.v is **embedded in
the binary at build time** — certification works from any cwd (the product runs in the
user's project, not this repo).

## Exit codes
0 ok · 1 check/certify failed (honest negative) · 2 usage/parse/bad ref · 3 signature gate ·
4 under-spec acknowledgment needed · 5 agent backend unusable · 6 missing prerequisite.

## What this supersedes / defers
Supersedes nothing in the KB (it realizes ADR-014/016/017); the v2 watcher tree (`lib/`,
`bin/`, `prompts/`, `test/`) is now dead code pending a retirement pass (delete + README/
WALKTHROUGH/opam rewrite). Deferred: an `accept <proposal>` command (one-writer purity says
`mv` is the acceptance act; revisit if editor round-trips prove painful); tier-B/C execution
harnesses; the guidance→R mechanical conflict check (ADR-017); hints channel-ref syntax.
