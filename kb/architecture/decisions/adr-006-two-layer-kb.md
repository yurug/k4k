---
id: adr-006
type: decision
summary: Two distinct KBs — `kb/` describes k4k itself; `.k4k/` (in target projects) describes the program k4k is currently building. The two follow the same agentic-dev-kit layout.
domain: architecture
last-updated: 2026-05-02
depends-on: [domain.prd, glossary]
refines: []
related: [spec.config-and-formats, properties.functional, conventions.context-economy]
---

# ADR-006: Two-layer KB — meta (`kb/`) and target (`.k4k/`)

## Status
Accepted (2026-05-02).

## Context
Round 2 user-edit of Q17 broadened `.k4k/` to also adopt the agentic-dev-kit KB structure (GLOSSARY, INDEX, indexes/, domain/, spec/, …). This raises:
- *Whose* KB is the one inside `.k4k/`?
- How does it coexist with the operational state (characterization/, gap/, agent-runs/, verifier-runs/)?
- Who writes it, and what happens if the user hand-edits a generated file?

Two readings:
1. **`.k4k/` documents the target program** (the program k4k is building right now).
2. **`.k4k/` documents the workings of k4k** in this particular run.

Reading (1) is more useful: future agents that pick up the target program (with or without k4k) read `.k4k/INDEX.md` and find a project-shaped KB. k4k's own docs (this file, you are reading them) live elsewhere.

## Decision
1. **`kb/`** in the k4k repository is the **meta KB**. It documents k4k itself. Authored by humans + Claude Code following the agentic-dev-kit methodology.
2. **`.k4k/`** in any target project is the **target KB**, side-by-side with operational state in the same directory. It documents the program k4k is currently building. Generated and maintained by k4k.
3. The two KBs follow the **same on-disk layout** (GLOSSARY.md, INDEX.md, indexes/by-task.md, domain/, spec/, properties/, architecture/, external/, conventions/, runbooks/, reports/) so an agent moving between them does not have to re-learn navigation.
4. **Authority:** the meta KB's authority is the human reviewer of the k4k repo. The target KB's authority is the *formal characterization* (`.k4k/characterization/desired/spec.json`) — KB content is *derived*; if it disagrees with `desired/spec.json`, the JSON wins.
5. **Ownership flips** (per ADR-005's hash mechanism) apply to target KB files identically to interaction-file sections. User edits to target KB are inviolable.
6. **Regeneration is incremental** (`P16`): only files whose source-of-truth aspects changed are regenerated, and only those still owned by k4k.

## Consequences
- Documentation cost is paid by k4k automatically — every target program ends up with a navigable KB.
- Two layouts to maintain in tests and generators; same skeleton mitigates this.
- The boundary is rigid: `kb/` *never* references `.k4k/` content directly; `.k4k/` *never* talks about k4k internals (it's the target program's docs).

## What this means for implementers
- **Never conflate the two.** Code that references "the KB" must always disambiguate.
- **Generators live in `lib/Kb_regen`**, not in `lib/Persist`. The generator is a transformation `(D, S) -> KB-files`; persistence is `KB-files -> disk`.
- **Auditing meta-KB drift is human work**; auditing target-KB drift is automatic (covered by `P16` and the audit checklist).
- **`indexes/by-task.md` exists in both layers**, but with different task lists: in `kb/` the tasks are "implement k4k feature X"; in `.k4k/` the tasks are "extend the target program with feature Y".
