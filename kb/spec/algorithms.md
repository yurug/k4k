---
id: spec.algorithms
type: spec
summary: The procedures k4k runs — stability check, formalization pass, canonicalization, gap construction, risk-score, gap-step loop, KB regeneration, ownership-flip detection.
domain: spec
last-updated: 2026-05-02
depends-on: [glossary, spec.data-model, spec.config-and-formats]
refines: []
related: [spec.api-contracts, properties.functional, architecture.overview]
---

# Algorithms

## One-liner

Every procedure k4k runs, expressed as deterministic pseudocode. No agent judgment is admitted on any branch — only verifier output and human input gate state transitions.

## Scope

Procedures only. Schemas in `data-model.md`; serialization in `config-and-formats.md`; interfaces (agent backend, verifier) in `api-contracts.md`.

## Top-level loop

```
main(file.k4k):
  parse_frontmatter_and_sections(file)
  read_or_init_manifest(.k4k/)
  loop:
    stability = stability_check(file)
    if not stability.is_stable: append_clarification_block(file, stability.questions); exit 1
    G = gap_construction(D, S)
    if G is empty: print "done"; exit 0
    if --max-steps reached or budget exhausted: exit 4
    step(G)              # one gap-step; updates .k4k/, may modify source tree
```

## Stability check {#stability}

Two-stage: structural, then semantic.

**Structural:** parse YAML frontmatter (`EFORMAT` on schema violation); split the body into Markdown sections by H2 heading and normalize each heading text into a section ID (`spec/config-and-formats.md#section-identification`); reject duplicate IDs (`EFORMAT`); confirm every required section ID for `class` is present and non-empty (`EUNSTABLE`).

**Semantic — formalization pass {#formalization}:**
1. Compute `user_sections_hash = sha256(concat(sorted(user-owned sections)))`.
2. If `manifest.desired.last_user_section_hashes` matches AND `desired/spec.json` exists, **skip** the pass and reuse `D`.
3. Otherwise: run `formalize(file)` twice independently (different agent seeds). Each run sends the prompt template `prompts/formalize.md` with user sections inlined; the response is validated against `Characterization` (`data-model.md`) then canonicalized ({#canonicalize}).
4. Both canonical hashes equal: `D = result`, persist to `desired/spec.json`, mark stable.
5. Hashes differ: emit a *divergence report* listing the differing AST nodes; append a clarification block to the interaction file; mark unstable.
6. Both attempts parse-fail: emit `EUNSTABLE` with the parse errors; mark unstable.

**Coverage check:** after successful formalization, run the *coverage checklist* for `class` (see `data-model.md#coverage-checklists`) against `D`. Missing aspect ⇒ unstable + clarification questions.

Stochastic agents producing non-equivalent translations of the same text *is* the signal of ambiguity. The two-run protocol turns it into a deterministic comparison (ADR-005).

## Canonicalization {#canonicalize}

Input: a `Characterization` AST. Output: a deterministic byte-identical canonical form.

```
canonicalize(c):
  c.argv               = sort_by_name(c.argv)
  c.errors             = sort_by_id(c.errors)
  c.fs_contract.reads  = sort_by_glob(c.fs_contract.reads)
  c.fs_contract.writes = sort_by_glob(c.fs_contract.writes)
  c.examples_accept    = sort_by_name(c.examples_accept)
  c.examples_refuse    = sort_by_name(c.examples_refuse)
  c.exit_codes         = sort_by_code(c.exit_codes)
  for every free-form string field s:
    s = s.strip().squeeze_whitespace()
  c.hash = sha256(json_dumps(c, sort_keys=true, ensure_ascii=true, indent=none))
  return c
```

**Note:** identifiers (e.g. `ArgSpec.name`, `ErrorEntry.id`) are user-defined and *not* renamed. Canonicalization sorts them but does not rewrite them. The user's ids carry semantic meaning (used in test names per `Verifier.dune-ocaml`'s convention).

## Property IDs {#property-ids}

For each aspect entry in `D`, derive a property ID:

```
property_id(aspect_path) = "P" || stable_hash_short(aspect_path)
```

`stable_hash_short` is the first 7 hex chars of `sha256(aspect_path | length-prefixed)`. IDs are stable across runs as long as the aspect's path is unchanged. If two aspects collide (probability negligible at v0 scale; auditable), append a counter: `P<hash>-2`.

## Gap construction

```
gap_construction(D, S):
  required = properties_from(D)         # one Property per aspect entry, status="required"
  for p in required:
    if p in established_in(S):
      p.status = "established"
      p.evidence += ref(latest_verifier_run)
    elif p in contradicted_by(S):
      p.status = "contradicted"
    else:
      p.status = "unknown"
  G = [p for p in required if p.status != "established"]
  for p in G: p.risk_score = risk_score(p)
  return G
```

## Risk score {#risk-score}

Deterministic, no agent input.

```
risk_score(p):
  severity      = severity_of_aspect(p.source.aspect)        // table below
  uncertainty   = 1.0 if p.status == "unknown" else 0.5      // contradicted is well-known-bad
  blast_radius  = blast_table(p.source)                       // 1.0 for spec, 0.5 for examples
  return severity * uncertainty * blast_radius

severity_table = {
  "errors":            1.0,
  "fs_contract":       0.9,
  "exit_codes":        0.8,
  "examples_refuse":   0.8,
  "inputs_outputs":    0.7,
  "examples_accept":   0.6,
  "concurrency":       0.5,
  "perf":              0.4,
  "goal":              0.2,
  "out_of_scope":      0.2
}
```

Tie-break by lexicographic order of `property.id` so the choice is stable.

## Gap-step {#gap-step}

```
step(G):
  p = argmax(p.risk_score for p in G)             # tie: lex order
  if p.failure_count >= 3:
    mark_blocked(p); append_clarification(p); return
  branch = git_create_scratch_branch(p.id)
  prompt = compose_prompt(p, S)                    # uses prompts/gap-step.md template
  resp   = agent_backend.invoke(prompt)            # see api-contracts.md
  if resp.outcome == "budget-exhausted": exit 4
  diff = extract_diff(resp.text)
  apply(diff, branch)
  vresult = verifier.run(branch, focus=[p.id])     # see api-contracts.md
  if vresult.by_property[p.id] == "established"
     and not regressed(vresult, S):
    git_merge(branch); update(S, vresult); persist_artefacts(); return
  else:
    git_discard(branch); p.failure_count += 1
    persist_artefacts(); return
```

## KB regeneration {#kb-regen}

After every gap-step that mutates `S`:
```
changed_facts = diff(prev_S, current_S) ∪ diff(prev_D, current_D)
for fact in changed_facts:
  for kb_file in manifest.kb_source_map.reverse_lookup(fact):
    if owner(kb_file) == "user": continue       # respect user edits
    regenerate(kb_file, current_S, current_D)   # prompts/kb-regen.md
    update_hash(kb_file)
manifest.update()
```
Full regeneration only on `--reset`.

## Ownership-flip detection {#ownership}

**Interaction-file ownership is no longer detected by hash matching** — per ADR-010, k4k delegates interaction-file concurrency to `cotype`, which uses 3-way merge (`diff3`) on every save against a captured base SHA. The "user took over a k4k-managed section" scenario surfaces as a `cotype save → conflict` outcome, not as a hash mismatch in k4k.

For **target-KB files under `.k4k/`** (which are NOT mediated by cotype — see ADR-006/007 for the two-layer KB scope), k4k still uses the hash-based ownership-flip mechanism: on read, recompute body hash; mismatch → treat as user-owned for this run, log `ownership.flip`, skip regeneration. The user's edit is the source of truth.

## Concurrent edits {#concurrent-edits}

The user may edit `<file.k4k>` while k4k runs. Contract (per ADR-010):
1. k4k reads the interaction file via `cotype open`, never directly. The result is a base SHA + a path to a frozen base snapshot k4k operates on.
2. k4k splices its edits *only into k4k-managed sections* (`## k4k:clarification:*`); user-owned sections flow through byte-for-byte from the base snapshot.
3. k4k writes via `cotype save --base-sha <captured>`. cotype performs a 3-way merge against the user's intervening edits.
   - `direct` → no concurrent user edit; k4k's bytes were written.
   - `merged` → user edited a non-overlapping region; cotype merged cleanly.
   - `conflict` → user edited a `## k4k:clarification:*` section. k4k surfaces the conflict path and exits with `ESTATE_CORRUPT` (exit 5); the user resolves the diff3 markers in their editor and runs `cotype resolve`.
4. cotype holds an internal `flock` on its sidecar for the duration of any mutating command — k4k itself never calls `flock`.

## Termination

- `--max-steps N`: hard limit on gap-step iterations.
- `SIGINT`/`SIGTERM`: set a flag checked at every safe point (between gap-steps and inside the verifier polling loop). Ensure `≤ 5 s` from signal to exit (`NF1`).
- Budget exhaustion: graceful exit with `EBUDGET`.

## Agent notes

> **The whole point of this file** is that every branch is justified by a deterministic predicate over `(D, S, verifier output, user input)` — never by an agent's judgment. If you find yourself writing "the agent decides ..." on a state-change path, stop and reconsider.
>
> **Two runs are the minimum.** If a future cost optimization tempts you to run the formalization pass once, remember: a single run cannot detect ambiguity. The whole semantic-stability story collapses.

## Related files

- `spec.api-contracts` — agent and verifier interfaces invoked above
- `spec.data-model` — types `D`, `S`, `Property`, `Manifest`, …
- `properties.functional` — invariants these procedures enforce
- `architecture/decisions/adr-005-canonical-ast.md` — why canonicalization is the determinism boundary
