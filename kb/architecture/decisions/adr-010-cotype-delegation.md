---
id: adr-010
type: decision
summary: k4k delegates the user-agent interaction-file concurrency protocol to `cotype` (a small CLI providing 3-way-merge safe-save). The hand-rolled ownership-tag scheme + flock from ADR-002 + audit gap H2 is replaced.
domain: architecture
last-updated: 2026-05-03
depends-on: [adr-002, glossary, external.cotype]
refines: [adr-002]
related: [adr-008, adr-009]
---

# ADR-010: Delegate user-agent interaction-file concurrency to cotype

## Status
**SUPERSEDED by ADR-014 (2026-06-19).** The v3 reorientation removes cotype entirely: the spec has one writer (the human); the agent proposes edits it never commits, so there is no concurrent-edit problem to merge. `lib/cotype*` and the cotype runtime dependency are dropped. Retained for history. — *Originally:* Accepted (2026-05-03). Partially supersedes ADR-002 (the interaction-file format simplifies — ownership tags removed).

## Context

The interaction file is the user's contract with k4k (per ADR-002). Two writers edit it: the user (authoring spec, answering clarification questions) and k4k (appending clarification blocks when stability fails). v0 coordinated this with three pieces of in-tree machinery:

1. **HTML ownership tags** (`<!-- k4k:owner=user begin id=X -->...<!-- end -->` and the symmetric `owner=k4k` form, with a `hash=H` attribute on k4k-owned regions). `lib/parser_sections.ml` (~130 lines) parses them.
2. **Hash-based ownership-flip detection** (P14 + T18): when reading a `k4k`-owned region, recompute the body hash; mismatch → treat as user-owned for this run.
3. **`flock(2)` discipline** on writes (P12, added in audit gap H2 as `lib/persist_lock.ml`).

Together these solve "user and k4k editing the same file without lost updates" — but they solve it twice over, with k4k carrying the implementation. The user separately built [`cotype`](https://pypi.org/project/cotype/), a small CLI that solves exactly this concurrency problem with a cleaner model: 3-way merge over POSIX `diff3`, optimistic concurrency, no in-document tags. cotype is independently maintained, used by editor integrations, and version-stable.

The same architectural principle that drove ADR-008 (verifier-agnostic) and ADR-009 (backend-agnostic) applies: **k4k should not reinvent concurrent-edit safety inside `lib/`** when a dedicated tool exists.

Unlike ADR-008/009, cotype is not a pluggable wire-protocol surface — it is a single tool we hardcode as a runtime dependency, like git. There is no abstract "concurrent-edit protocol" to abstract over multiple implementations; cotype IS the protocol, the same way git IS version control for k4k's purposes.

## Decision

1. **k4k depends on `cotype` at runtime** (user installs via `pipx install cotype` or `pip install cotype`). Documented in `external/cotype.md`. Missing binary → startup-time error with installation hint.
2. **Every k4k mutation of the interaction file goes through cotype** following its documented agent protocol: `cotype open` → splice → `cotype save --base-sha`. The k4k wrapper (`lib/cotype.ml`) enforces the load-bearing "read from `base_path`, never from FILE directly" rule.
3. **HTML ownership tags are removed from the interaction-file format.** ADR-002's `<!-- k4k:owner=... -->` syntax is dropped; the file is plain Markdown + YAML frontmatter. k4k-managed sections are identified by a stable heading pattern: `## k4k:clarification:<timestamp>`. All other sections are the user's.
4. **`lib/persist_lock.ml` is removed.** P12 (file-locking discipline) is satisfied by cotype's internal `flock` on its own sidecar lock.
5. **Hash-based ownership-flip detection is removed** from k4k's parser. P14 (ownership-flip on hash mismatch) and T18 (user overrides a `k4k`-owned KB file) are restated in terms of cotype's `conflict` outcome.
6. **`lib/parser_sections.ml` shrinks** to a plain Markdown-section-by-heading parser (no tag grammar). The `hash=` attribute parsing is gone.
7. **The structural-splicing recipe** cotype recommends in its docs is naturally what k4k does anyway: parse the interaction file into sections; when k4k writes, copy non-k4k-managed sections byte-for-byte from `base_path` and only rewrite the `## k4k:clarification:*` blocks. User-vs-k4k edits become non-overlapping by construction; conflict outcomes only occur when the user explicitly edits a `## k4k:clarification:*` section.

## Consequences

**Wins:**
- `lib/` shrinks. `parser_sections.ml` simplifies (Markdown headers only, no tag grammar). `persist_lock.ml` is deleted. The `hash=` attribute on the k4k-owned tags is gone.
- The interaction file format simplifies for users. No more HTML comments cluttering specs; just plain Markdown + frontmatter.
- The `T8` edge case ("user hand-edits a `k4k:owner=k4k` section") is no longer a *k4k* concern — it's cotype's `conflict` outcome, surfaced uniformly with any other concurrent-edit collision.
- `NF6` (system-level determinism) extends naturally to cotype-mediated writes; cotype is itself deterministic.
- k4k composes with editor integrations that already speak cotype (Emacs, others). A user editing the file in Emacs while k4k runs gets the same safety properties — without k4k knowing about Emacs.

**Costs:**
- New runtime dependency (`cotype`, plus its transitive `Python ≥ 3.11` and POSIX `diff3`). Documented at startup; missing binary fails fast with a clear message.
- `bin/main.ml` startup must `cotype init` the interaction file if the sidecar is absent. Idempotent and cheap.
- Existing `.k4k` fixtures in this repo lose their ownership tags; tests that assert on tag presence are rewritten in terms of cotype's outcomes.
- The PRD historical note (in `kb/plan.md`) gains another paragraph documenting this retrofit, like the ADR-008 / ADR-009 ones.

**v2+ implication:**
- If the user wants k4k to play nicely with other agents (e.g. a reviewer agent that critiques the spec while k4k drives implementation), cotype's `--actor` label and 3-way merge already handle it. ADR-010 is forward-looking past v0.

## Migration story for v0+ users

Anyone running k4k pre-ADR-010 must:
1. `pipx install cotype` (or `pip install cotype`).
2. Strip the HTML ownership tags from their `.k4k` files. The `goal`, `inputs-outputs`, etc. sections become plain Markdown headings without `<!-- k4k:owner=user -->` wrappers.
3. Run `k4k <file.k4k>` as before; on first run, k4k auto-runs `cotype init` to create the sidecar. No further user action.

Old fixtures with ownership tags are not rejected outright — k4k's parser ignores the tags as plain HTML comments — but the `hash=` attribute is no longer interpreted. Effectively a no-op for migration; the tags are inert text.

## What this means for implementers

- **Never read FILE directly.** Use `Cotype.open` → returns base-path → read from base-path → splice → `Cotype.save`. The OCaml wrapper enforces this; bypassing it is a panic-class violation.
- **Never call `flock` from k4k code.** cotype's sidecar lock is the single source of truth.
- **Never re-introduce ownership tags.** ADR-010 is normative.
- **The k4k-managed-section heading pattern is `## k4k:clarification:<timestamp>`.** Stable across versions; do not rename without a `k4k.version` bump.
- **`lib/cotype.ml`** is the only module that shells out to `cotype`. ≤ 200 lines per the code-style cap.
- **Tests that previously exercised ownership-tag round-trip** (`P1_ownership_user_section_unchanged`, `P14_ownership_flip_*`, `T8_hand_edited_owner_k4k_section_flips_ownership`) are rewritten in terms of cotype's outcomes (`direct` / `merged` / `conflict`).

## Relationship to ADR-002 and ADR-008/009

ADR-002 said the interaction file uses HTML ownership tags. ADR-010 keeps the *file format* claim (Markdown + YAML frontmatter) and drops the *ownership-tag mechanism*. The header bookkeeping moves from in-document tags to cotype-managed sidecar metadata.

ADR-008 (verifier-agnostic) and ADR-009 (backend-agnostic) extracted *pluggable* concerns to wire-protocol layers. ADR-010 extracts a *singular* concern (concurrent-edit safety) to a hardcoded dependency. Same principle ("k4k should not reinvent what already exists, better, outside `lib/`"), different shape (one tool, not a pluggable surface).
