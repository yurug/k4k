---
id: adr-002
type: decision
summary: The interaction file is Markdown + YAML frontmatter + HTML-comment ownership tags. The CLI never writes inside `owner=user` regions.
domain: architecture
last-updated: 2026-05-02
depends-on: [domain.prd, glossary]
refines: []
related: [spec.config-and-formats, properties.functional]
---

# ADR-002: Markdown interaction file with HTML-comment ownership tags

## Status
Accepted (2026-05-02). **Partially superseded by ADR-010** (2026-05-03): HTML ownership-tag mechanism replaced by cotype delegation. **Further refined by the v2 reorientation** (2026-05-08): the file format simplifies again (no user-facing tooling configuration in YAML frontmatter — k4k self-selects verifier and backend). k4k-managed section conventions broaden to four kinds (`## k4k:status`, `## k4k:version:<n>`, `## k4k:clarification:<ts>`, `## k4k:tradeoff:proposal:<ts>`). The user's surface is the file alone — no flags, no tool config. The *file format* claim (Markdown + YAML frontmatter, `*.k4k` extension) stands across all three revisions.

## Context
NOTES.md introduces the *interaction file* as the user's contract with k4k. It must:
- Be authoritative *for the user* — they must trust k4k will not silently mutate their words.
- Be *machine-extensible* — k4k must be able to append clarification questions without conflicting with the user's content.
- Be cheap to render and review — humans must be able to read and edit it without specialized tools.

Alternatives considered:
- TOML or JSON: machine-friendly, human-hostile for prose-heavy specs.
- Custom DSL: yet another thing to learn; raises the cost of every edit.
- Pure Markdown (no ownership tags): no way to mark machine-managed regions.

## Decision
- The file extension is `*.k4k`.
- The body is **Markdown** with a top-level **YAML frontmatter** block carrying the configuration (`version`, `class`, `budget`, `retention`).
- Ownership of each section is declared with **HTML comments**: `<!-- k4k:owner=user begin id=<section-id> -->` ... `<!-- k4k:owner=user end -->`. Same form with `owner=k4k` plus a `hash=<sha256>` attribute that lets k4k detect manual edits.
- k4k *never* writes inside `owner=user` regions. This is enforced both by code (panic on attempt) and by the test suite.
- Hand-edits to `owner=k4k` regions flip ownership to `user` (per ADR-005's hash-based detection).

## Consequences
- Humans can render the file in any Markdown viewer with no special knowledge of k4k.
- Diff output (in PRs, in `git log`) is line-based and review-friendly.
- The ownership tags are slightly noisy; we accept that for the safety guarantee.
- The 10 MB file-size cap (`EFILE_TOO_LARGE`) is set far above what any well-formed spec needs; oversize is a sentinel for "the spec is no longer KISS".

## What this means for implementers
- The parser (`lib/Parser`) is the single source of truth for file ↔ in-memory structure.
- All writes to `<file.k4k>` go through `lib/Persist.append_clarification` — no other module is allowed to write the file.
- Adding a new required section means: (a) add the id to `spec/data-model.md#coverage-checklists`, (b) bump `k4k.version` in `spec/config-and-formats.md`, (c) write a migration story in this ADR's successor.
- Section IDs are part of the wire contract. Renaming = breaking change.
