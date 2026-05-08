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

The v2 binary is an autonomous watcher daemon (ADR-011 / ADR-013).
The user runs `k4k <file>` once; thereafter the watcher polls the
file via cotype and drives versions to completion without further
operator action. Termination is signal-driven (SIGINT / SIGTERM) or
via the documented test-only `--exit-on-stable` / `--exit-on-done` /
`--max-versions=N` flags.

```
main(file.k4k):
  Watcher.startup(file):                # ADR-011 §3
    ensure_starter_file(file)           # creates a template if missing
    ensure_frontmatter(file)            # auto-injects k4k:{version,class}
    ensure_git_repo(dirname file)       # git init if not a work tree
    ensure_toolchain("cotype", "git")   # ADR-012 §4
    Watcher_pid.acquire(.k4k/)          # ADR-011 §2: single instance per file
  agent_invoke = Watcher_dev.resolve_invoke()
                                         # ALLOCATED ONCE; queues persist
  loop until SIGINT or test-flag exit:
    if user_directives_in_file include `request: rollback`:
      rollback(current_version_branch)
      stop                              # ADR-013 §2 step 6
    if `request: pause`: sleep poll_interval; continue
    content = Cotype.read_base(file)    # ADR-010
    structural = stability_check(content)
    if structural.unstable:
      append_clarification_block(file, structural.questions)
      sleep poll_interval; continue     # NEVER exits — ADR-011 §1
    process_stable():                   # archive resolved clarifications;
                                        # auto-delete the welcome block
                                        # (ADR-011 §7)
    outcome = attempt_version(content, agent_invoke)
                                         # see "Version loop" below
    if outcome is Done:                 versions_done += 1
    if exit_on_done and outcome ∈ {Done, Rolled_back}: stop
    if max_versions and versions_done ≥ max_versions: stop
    sleep poll_interval                  # default 500 ms (2 Hz)
```

The watcher never `exit`s on instability — it appends a
clarification block and continues polling. The only "termination"
in production is a signal; the test-only flags (`--exit-on-stable`,
`--exit-on-done`, `--max-versions`) let integration tests bound a
run deterministically.

### Version loop (per stable tick)

```
attempt_version(content, agent_invoke):
  d = formalize(content, agent_invoke) # see {#formalization}
  if d is Error reason: emit version.skip; return Skipped
  if d.hash == last_completed_d_hash:  # idempotence gate
     emit version.skip "no-spec-change"; return Skipped
  v = Version.start_new(branch=k4k/version/<n>, baseline=HEAD,
                        d_hash=d.hash)
  drive_version(d, v):                  # ADR-013 §2
    write_developing_status(file)       # splice ## k4k:status block
    baseline_user_hashes = snapshot()
    for property p in argmax-lex order on D:
      Version_user_edits.check_and_queue(baseline)
                                         # P22: if the user edited
                                         # mid-flight, surface the
                                         # count and commit the
                                         # residue on the version
                                         # branch (NEVER interrupts
                                         # the gap loop)
      drive_property_at_tier_a(p):       # see "Gap-step" below
        Accepted     → record commit
        Done_blocked → defer
        Tradeoff     → propose to user, wait for sign-off
                       (Tradeoff_flow), retry at the approved tier
                       OR at Tier-A with the user's guidance
        Stop         → SIGINT / budget exit
    Version_finalize.finalize:
      if every property is established → merge to default branch,
                                         tag v<n>, write audit.md →
                                         return Done
      else                              → write audit.md, leave
                                         the branch around → return
                                         Rolled_back
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

**v2 direct-commit workflow** (ADR-013 §2 step 3, post-v2-batch-4a):
the caller is responsible for being on the correct version branch
([`k4k/version/<n>`]); `Gap_step` applies the diff directly to the
working tree, runs the verifier, and either commits-on-the-spot
(Accepted) or `git reset --hard HEAD` (rewinds to the last accepted
commit). The previous v0/v1 scratch-branch indirection
(`k4k/gap/<pid>/<ts>`) is gone; branches are now managed one level up
by `Version_loop`.

```
step(p, prev_status):
  preflight: working tree must be clean and a git repo
  if p.failure_count >= 3 or p.blocked: return Blocked p
  prompt = compose_prompt(p, S, tier)              # uses prompts/gap-step.tier-{a,b,c}.md
  resp   = agent_backend.invoke(prompt)            # see api-contracts.md
  if resp.outcome == "budget-exhausted": return Budget_exhausted
  diff = extract_diff(resp.text)
  Diff_filter.first_forbidden(diff)                # reject .k4k/, .git/,
                                                   # absolute, ../ paths
                                                   # before any FS write
  apply(diff, working_tree)                        # Git.apply_diff --index
  vresult = verifier.run(working_tree, focus=[p.id])
  if vresult.by_property[p.id] == "established"
     and not regressed(vresult, prev_status):
    Version.commit_accept(message="[k4k] establish <pid>")
    persist_artefacts(); return Accepted { property; commit_sha }
  else:
    Git.reset_hard(HEAD)            # rewind: drop diff + untracked
    p.failure_count += 1
    persist_artefacts()
    return Tradeoff if failure_count >= 3 else Rejected
```

`Tradeoff` (3-strikes) hands off to `Tradeoff_flow.propose_and_wait`
(ADR-011 §5): k4k splices a `## k4k:tradeoff:proposal:<ts>` block
into the interaction file via cotype, polls until the user replies
inline (`Approved: Tier B|C` or `Rejected: <guidance>`), archives
the proposal under `.k4k/version/<n>/tradeoffs/`, breadcrumbs the
in-file block, commits the residue on the version branch, and
retries at the user-approved tier (`Version_tradeoff.handle`). The
`p.blocked` short-circuit on a property whose `failure_count` is
already at 3 fires only when the property has been deferred at the
current tier and is being re-visited; the tier-reset
(`reset_for_tier`) before each retry zeroes both fields, so the
loop can re-converge under the new tier.

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
Full regeneration is unbounded — there is no `--reset` flag in v2.
A user who wants a clean rebuild deletes `.k4k/manifest.json` and
re-launches the watcher; user-owned content in the interaction file
itself is untouched.

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

The v2 watcher is intentionally signal-driven; it has no
production termination flag. The five exit paths are:

- **`SIGINT` / `SIGTERM`**: cooperative shutdown via `Sigint`. Each
  loop checks `Sigint.should_exit ()` at every safe point (between
  gap-steps, before each agent invocation, inside the verifier
  polling loop). NF1: `≤ 5 s` from signal to exit.
- **Startup-phase error**: `Watcher.startup` typifies any caught
  exception (including bare `Unix.Unix_error` from mkdir/open) into
  the closed `Error.error` taxonomy and returns `Aborted msg`; the
  binary prints `k4k: <msg>` to stderr and exits with the
  category's exit code (1/2/3/4/5/64 per
  `kb/spec/error-taxonomy.md`).
- **PID collision**: another live watcher already owns
  `.k4k/watcher.pid`; exit 5.
- **Test-only flags** (kb/runbooks/test-environment.md): the
  watcher returns cleanly after `--exit-on-stable` (first stability
  snapshot), `--exit-on-done` (any terminal version outcome —
  `Done` or `Rolled_back`), or `--max-versions=N` (after N terminal
  versions). Production never sets these.
- **Budget exhaustion**: per-version budget is internal-only in v2;
  it is tracked as a `version.skip` event and surfaced in the
  status block, not as a process exit.

## Agent notes

> **The whole point of this file** is that every branch is justified by a deterministic predicate over `(D, S, verifier output, user input)` — never by an agent's judgment. If you find yourself writing "the agent decides ..." on a state-change path, stop and reconsider.
>
> **Two runs are the minimum.** If a future cost optimization tempts you to run the formalization pass once, remember: a single run cannot detect ambiguity. The whole semantic-stability story collapses.

## Related files

- `spec.api-contracts` — agent and verifier interfaces invoked above
- `spec.data-model` — types `D`, `S`, `Property`, `Manifest`, …
- `properties.functional` — invariants these procedures enforce
- `architecture/decisions/adr-005-canonical-ast.md` — why canonicalization is the determinism boundary
