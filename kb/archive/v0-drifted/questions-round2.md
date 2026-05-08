---
phase: 1
round: 2
created: 2026-05-02
status: awaiting-user
follows: questions-round1.md
---

# k4k — Round 2 Ambiguity Resolution

> **Why a round 2?**
> In round 1 you strengthened Q13 (stability now requires no semantic ambiguity AND adequate intent coverage) and broadened Q17 (`.k4k/` should also follow the agentic-dev-kit KB layout). Both edits ripple into the harness algorithm and the on-disk model. This round zooms in on those two areas only — everything else from round 1 is taken as accepted.
>
> Same conventions: each question has a *Default* I propose. Edit in place, replace `Default:` with `Answer:` for overrides, write `TBD` if still open, add new questions under *§ User-added*. Tell me to proceed when done.

---

## § Stability: how do we mechanically detect "no ambiguity"? (Q13 follow-ups)

The round 1 default ("required sections present + non-empty + parses unambiguously") was a *structural* check. Your strengthened definition adds a *semantic* check: a formal specification must be writable, AND the user's intent must be adequately covered. Mechanizing those two clauses is the whole game — please pin down how.

**13a. Mechanism for "no ambiguity / a formal specification can be written".**
Default: A *formalization pass* — k4k translates the user-owned sections into an internal characterization (a typed AST: signatures of inputs/outputs, pre/post-conditions, accepting examples, refusing examples, …). The translation is performed by the coding-agent backend constrained by a strict grammar; the result is checked against the schema with a deterministic parser. Stability requires: (i) at least one syntactically valid translation exists, AND (ii) all valid translations are *semantically equivalent* up to renaming (checked by a structural diff). If the agent produces two non-equivalent translations from the same spec, the spec is ambiguous; k4k surfaces the divergence to the user.

**13b. Mechanism for "covers enough aspects to capture user intent".**
Default: A *coverage checklist* keyed on the program class declared in the interaction file's YAML frontmatter (`class: cli | library | filter | …`). Each class has a fixed list of required aspects (e.g. for `cli`: inputs, outputs, exit codes, stdout/stderr split, error taxonomy, concurrency expectations, performance bounds-if-applicable, file-system contract). An aspect is "covered" iff a section in the interaction file mentions it AND the formalization pass produced a non-trivial entry for it. Missing or empty entries → unstable.

**13c. What does k4k do when semantic instability is detected?**
Default: Append a fresh `<!-- k4k:owner=user begin id=clarification-<timestamp> -->` block to the interaction file containing concrete clarifying questions (one per ambiguity / missing aspect), exit 1, and print a one-line status pointing the user to that block. The user edits answers in place and re-runs `k4k`. No ambient daemon, no chat loop — the file is the only channel.

**13d. Pass/fail or graded?**
Default: Strict pass/fail. Reason: a graded score invites the user to ship "76% stable" specs, which defeats the harness's correctness guarantees. The cost is forcing the user to resolve every ambiguity; that's a feature, not a bug.

**13e. Does the formalization pass count against the agent budget (Q28)?**
Default: Yes. It runs a single agent call per attempted translation; same hard/soft caps apply. If the budget is exhausted before a translation is produced, k4k exits with `unstable: budget-exhausted` and the user can either raise the cap or simplify the spec.

**13f. Where is the resulting formal characterization stored?**
Default: `.k4k/characterization/desired/spec.json` (the canonical AST) plus a human-readable mirror at `.k4k/characterization/desired/spec.md`. Both regenerated on every stability check; the human-readable mirror lives under `owner=k4k` so the user can review but not authoritatively edit.

**13g. Re-stability check on every run, or cached?**
Default: Cached by hash of the user-owned sections. If the hash matches, skip the formalization pass and reuse `.k4k/characterization/desired/`. If any user-owned section changed, re-run.

**13h. Is the program class (Q13b) declared by the user, or inferred?**
Default: Declared, in the YAML frontmatter (`class: cli`). v0 supports `cli` only; other classes raise an error directing the user to declare `cli` or wait for v1. This is a deliberate narrowing — class-specific coverage checklists multiply the spec/test surface, and v0 ships one.

---

## § `.k4k/` layout: how do the two KB layers coexist? (Q17 follow-ups)

Your edit asks `.k4k/` to also adopt the agentic-dev-kit KB structure (GLOSSARY.md, INDEX.md, indexes/, domain/, spec/, properties/, architecture/, external/, conventions/, runbooks/, reports/) on top of the k4k-specific dirs (characterization/, gap/, agent-runs/, verifier-runs/, manifest.json). Several questions follow.

**17a. Whose knowledge base is the agentic-dev-kit-style KB inside `.k4k/`?**
Default: The KB *of the program k4k is building*, not k4k itself. Reason: it lives next to that program's source. It documents the spec/properties/architecture of the target software, in the form best understood by future agents that may extend it. (k4k's own KB — the one we're about to write in `/home/coder/workspace/k4k/kb/` — describes the `k4k` tool itself.)

**17b. Who writes the content of `.k4k/<kb-files>`?**
Default: k4k scaffolds the directories and seed files; the coding-agent backend drafts initial content from the interaction file's user-owned sections and the formal characterization in `.k4k/characterization/desired/`; the user may edit any file. Edits to KB files are not authoritative for the harness — only `.k4k/characterization/desired/` is. The KB is *derived documentation*, kept in sync with the characterization on every stable run.

**17c. Layout: side-by-side or nested?**
Default: Side-by-side at the root of `.k4k/`:
```
.k4k/
  # Agentic-dev-kit KB for the target program (auto-generated, derived):
  INDEX.md
  GLOSSARY.md
  indexes/by-task.md
  domain/prd.md
  spec/{data-model,algorithms,api-contracts,config-and-formats,error-taxonomy,INDEX}.md
  properties/{functional,non-functional,edge-cases,INDEX}.md
  architecture/{overview.md,decisions/}
  external/INDEX.md
  conventions/{code-style,error-handling,testing-strategy}.md
  runbooks/audit-checklist.md
  reports/

  # k4k-specific operational state:
  characterization/{desired,current}/
  gap/properties.json
  agent-runs/<timestamp-id>/{prompt.md,response.md,diff.patch,verdict.json}
  verifier-runs/<timestamp-id>/{stdout.log,stderr.log,result.json}
  manifest.json
  log.jsonl
```

**17d. Is the KB regenerated from scratch on every run, or incrementally updated?**
Default: Incrementally. On each gap-step that changes characterization or source, k4k regenerates only the KB files whose source-of-truth changed (tracked via `manifest.json`'s file→source map). Full regeneration on `--reset`.

**17e. Does interaction-file stability require the KB to exist or be consistent?**
Default: No. Stability is a property of the interaction file alone (per Q13). The KB is a downstream artefact produced *after* stability is established. KB inconsistencies are flagged as gaps in their own right and tackled like any other property.

**17f. Are auto-generated KB files marked machine-owned?**
Default: Yes. Each file has `owner: k4k` in its YAML frontmatter and a content hash; manual edits flip ownership to `user` (same model as the interaction file, Q16). User-owned KB files are not regenerated; their content is treated as authoritative.

**17g. Where do *audit reports* go (the agentic-dev-kit's `reports/` directory)?**
Default: `.k4k/reports/`. v0 generates one report after each Phase-5-equivalent audit pass: `reports/audit-<timestamp>.md` listing properties tested, results, and any criticals. The audit pass itself is part of the gap-step loop (every property has a corresponding test, and the verifier runs them).

---

## § Cross-cutting implications

**X1. Does the new Q13 mean Q14's required user-owned sections need to expand?**
Round-1 Q14 listed Goal, Inputs and outputs, Acceptance examples, Out of scope, Verifier preferences. The class-specific coverage checklist (Q13b) implies more for `class: cli`.
Default: For `class: cli` the *required* user-owned sections become:
- `## Goal` — prose
- `## Class` (or in YAML frontmatter) — `cli`
- `## Inputs and outputs` — args, stdin, stdout, stderr, exit codes
- `## Error taxonomy` — every error type, when raised, what the user sees
- `## File-system contract` — what files the program reads/writes, where
- `## Concurrency` — single-threaded? signal handling? (state "N/A" if not applicable)
- `## Performance bounds` — wall-clock or memory expectations, or "N/A"
- `## Acceptance examples` — ≥3 input/output pairs
- `## Refusing examples` — ≥1 input that must produce a specific error
- `## Out of scope` — explicit non-goals
- `## Verifier preferences` (optional)

**X2. The harness algorithm (Q22) currently kicks in *after* stability. Does the formalization pass also produce gap-step inputs?**
Default: Yes. The formalization output (`.k4k/characterization/desired/spec.json`) is the *source* for the property set in `gap/properties.json`. Each formal entry maps to one or more properties; risk-score (Q21) is computed from the formal entry's structure (e.g. error-path entries get higher risk than happy-path entries). This means the formalization pass is doing two jobs: gating stability AND seeding the property set.

**X3. Determinism with stochastic agent calls in the formalization pass.**
The formalization pass calls the agent (Q13a, Q13e). The agent is stochastic. Two stable runs on the same spec might therefore produce *syntactically* different formalizations even if both are correct.
Default: We canonicalize the AST after parsing (sort fields, normalize identifiers via a deterministic naming function keyed on user section ids). Two runs that produce equivalent ASTs hash the same; two runs that produce non-equivalent ASTs trigger the divergence path of Q13a. The harness's determinism contract from Q27 is preserved on the canonicalized AST, not on raw agent output.

---

## § User-added

(Add your own questions or override defaults in this section.)

At some point, I want us to also use LLM available through local Ollama. In that case, agents will need to be provided very optimized contexts because they are not as good as claude (with opus). Can we take that into account in the architecture and core principles of k4k?
