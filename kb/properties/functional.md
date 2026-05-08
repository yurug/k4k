---
id: properties.functional
type: spec
summary: Functional invariants P1..PN that k4k must enforce. Each entry includes a statement, violation example, justification, and test strategy.
domain: properties
last-updated: 2026-05-02
depends-on: [glossary, spec.algorithms, spec.api-contracts, spec.error-taxonomy]
refines: []
related: [properties.non-functional, properties.edge-cases, conventions.testing-strategy]
---

# Functional Properties (P-series)

## One-liner

Every invariant `k4k` must enforce on its own behavior, with one entry per property. Source code references these IDs in `@invariant` annotations; tests reference them in test names (`P4_canonical_ast_roundtrip`).

## Scope

Behavior of `k4k` itself. Behavior of the *target* programs k4k builds is described in their per-target `.k4k/properties/`, not here.

## Conventions

Each entry: **ID**, **Statement**, **Violation**, **Why**, **Test strategy**. Statements are unambiguous predicates; violations are the most diagnostic counter-example.

---

### P1 — Ownership inviolability
- **Statement:** For the interaction file, k4k never modifies bytes outside `## k4k:clarification:*` sections — user-owned sections of the interaction file are byte-equal pre- and post-write. (Realized via cotype's `base_path`-flow plus structural splicing; see ADR-010 and `external/cotype.md`.) For target-KB files under `.k4k/`, the original hash-based ownership-flip rule still applies (see P14).
- **Violation:** k4k overwrites the user's `## Goal` text during a stability run.
- **Why:** The interaction file is the user's contract. Any silent edit destroys trust and corrupts D-derivation. Per `kb/NOTES.md` and Q12.
- **Test strategy:** Property-based test — generate random interaction files, run k4k, assert byte-equality of every non-`k4k:clarification:*` section pre/post. Plus a positive test that `cotype save` is the only path through which `lib/cotype.ml` writes the interaction file.

### P2 — Two-stage stability
- **Statement:** Stability requires both structural validity *and* semantic validity (formalization + coverage); failure at either stage marks the file `unstable`.
- **Violation:** A file with all required sections present but containing a contradictory acceptance example is reported `stable`.
- **Why:** Stability is the whole point — see Q13 (round 1 user override).
- **Test strategy:** Unit tests with hand-crafted files exercising each failure mode; one integration test that walks the full path on a real spec.

### P3 — Pass/fail stability (no grading)
- **Statement:** `stability_check` returns a binary verdict; no partial credit, no score.
- **Violation:** API exposes `stability.score : float` somewhere.
- **Why:** Graded stability invites shipping near-stable specs, defeating correctness. See Q13d.
- **Test strategy:** Type-check / signature lint — `Stability.t` is `Stable | Unstable of issue list`. No float field anywhere.

### P4 — Determinism on canonical AST
- **Statement:** For the same `(file content, .k4k/ contents, agent backend version, verifier version)`, the canonicalized `D` and the resulting gap-property ordering are byte-identical across runs.
- **Violation:** Two runs of `k4k --check` on the same file produce different `desired/spec.json`.
- **Why:** Determinism is the harness's defining promise. The agent is stochastic; canonicalization is the deterministic boundary. See ADR-005.
- **Test strategy:** Run `k4k --check` 5× with stub agent that returns equivalent-but-syntactically-different ASTs; assert canonical hashes equal.

### P5 — Non-regression
- **Statement:** A property whose status was `established` cannot become non-`established` *as a result of k4k's actions alone*. Only a user-driven change to `D` can demote it.
- **Violation:** k4k applies a patch for property P7 that breaks the test for already-established P3, then accepts the patch.
- **Why:** Convergence absent regression is the only convergence guarantee k4k offers. See Q24.
- **Test strategy:** Integration test — establish two properties on a stub program; force the agent to propose a regressive patch on the third; assert the patch is rejected.

### P6 — Three-strikes-then-blocked
- **Statement:** A property whose `failure_count` reaches 3 within the current verification tier is marked `blocked` for that tier. k4k stops attempting it at the current tier and (per `domain/prd.md` v2) appends one of two block kinds to the interaction file: a `## k4k:clarification:<ts>` block when the failure indicates spec ambiguity, OR a `## k4k:tradeoff:proposal:<ts>` block when the property is well-specified but Tier A is genuinely too hard.
- **Violation:** k4k loops indefinitely on the same property at the same tier; OR k4k drops a property to a lower tier without surfacing the trade-off for user sign-off.
- **Why:** Bounded effort prevents ralph-loop runaway; the tier-negotiation protocol keeps the user in the loop on verification quality.
- **Test strategy:** Stub agent that always proposes invalid Tier-A patches; assert k4k surfaces a clarification or tradeoff block after exactly 3 attempts and pauses development without exiting.

### P7 — Closed error taxonomy
- **Statement:** Every user-visible error matches an entry in `spec/error-taxonomy.md`. Code that emits an unknown error is a bug.
- **Violation:** k4k prints `Error: something happened` with no code.
- **Why:** Auditability requires a finite, documented surface. See Q39 family.
- **Test strategy:** Lint pass over the source — every `raise` site has a matching ID; integration test that triggers each documented error and asserts exit code + stderr line.

### P8 — Bounded responsiveness to signals
- **Statement:** `SIGINT`/`SIGTERM` causes process exit within ≤ 5 s. (Measured in `properties/non-functional.md#NF1`.)
- **Violation:** k4k blocks for 30 s waiting on an HTTP timeout after Ctrl-C.
- **Why:** Users must remain in control. See Q24.
- **Test strategy:** Integration test — start k4k, send SIGINT during a (stubbed-slow) agent call, assert exit ≤ 5 s.

### P9 — Budget caps respected
- **Statement:** Each agent invocation (`Backend_external.invoke ~budget`) refuses with `Budget_exhausted` rather than exceeding the cap. Engine-level budget bookkeeping (the *internal* `hard_per_invocation` and per-version caps that k4k self-selects, no longer user-facing in v2) is honored: when the cap is reached, k4k pauses development and surfaces a `## k4k:tradeoff:proposal:<ts>` block proposing how to proceed (decompose the property, drop to a lower tier, etc.) — not an exit code.
- **Violation:** k4k spends past the cap silently; OR k4k crashes/exits when the cap is reached instead of opening an in-file negotiation.
- **Why:** Predictable cost; the user remains in control of verification quality without managing the cap directly.
- **Test strategy:** Stub agent that reports budget exhausted near the cap; assert k4k pauses, writes a `tradeoff:proposal` block, and waits.

### P10 — Atomic writes
- **Statement:** `manifest.json`, `gap/properties.json`, `desired/spec.json`, `current/spec.json` are written via tmp+fsync+rename. A `kill -9` mid-write never leaves a partial file.
- **Violation:** A reader observes `manifest.json` mid-truncate.
- **Why:** Crash safety; harness restartability. See `spec/config-and-formats.md`.
- **Test strategy:** Inject a crash hook between write and rename; restart k4k; assert prior state is intact.

### P11 — Stdout/stderr discipline
- **Statement:** The watcher emits **structured JSONL on stdout** (one event per state transition; mirrors `.k4k/log.jsonl`). stderr carries operator-level diagnostics under `-v` / `-vv`; nothing at default verbosity. The two streams never interleave. Free-form prose is forbidden on stdout.
- **Violation:** A warning string appears on stdout that does not parse as a JSON object.
- **Why:** Operators piping the watcher into log aggregators rely on stdout being machine-parseable. End users do not read stdout in v2 — they read the `.k4k` file's `## k4k:status` block.
- **Test strategy:** Run k4k under `2>/dev/null`, capture stdout, assert every non-empty line is parseable JSON; same with `1>/dev/null` for stderr at default verbosity (must be empty).

### P12 — Concurrency safety on the interaction file
- **Statement:** Concurrent writes to `<file.k4k>` (by the user, by k4k, or by other cooperating actors) never lose updates. Realized via `cotype` (`external/cotype.md`, ADR-010): every k4k-side mutation goes through `cotype open` → splice → `cotype save --base-sha`, with cotype's 3-way merge handling intervening user edits.
- **Violation:** A `k4k` clarification append silently clobbers the user's mid-run edit to a different section.
- **Why:** The user must remain able to edit while k4k runs (Q15, Q44).
- **Test strategy:** Two concurrent writers (one user-simulating, one k4k) edit different sections of the same file; assert both edits land. Plus a "user edits a `## k4k:clarification:*` section" test asserting k4k surfaces a `conflict` and exits gracefully (no silent overwrite).
- **Pre-ADR-010 history:** This property previously specified `flock(2)` discipline implemented in `lib/persist_lock.ml`. Both are gone; cotype handles the lock internally on its sidecar.

### P13 — Fresh-read per step
- **Statement:** k4k re-reads `<file.k4k>` (via `cotype open` returning a base path) at the start of every step; no in-memory cache survives across steps.
- **Violation:** A user edit to the file mid-run is visible only on next invocation.
- **Why:** The user owns the file; their edits are seen as soon as a step boundary admits them. See Q15.
- **Test strategy:** Modify the file between steps via a hook; assert next step sees the new bytes (via the new `cotype open` base SHA differing).

### P14 — Ownership-flip detection (KB files only, post-ADR-010)
- **Statement:** For target-KB files under `.k4k/`, reading a `k4k`-owned file with a `content_hash` mismatch flips ownership to `user` for the run and emits an `ownership.flip` log event. (For the interaction file, the equivalent scenario is now a `cotype save → conflict` outcome — see P12.)
- **Violation:** k4k regenerates a `.k4k/spec/data-model.md` the user has edited, silently overwriting their work.
- **Why:** User edits are inviolable; detection is via hash, not heuristic. See Q16. Target-KB files do NOT go through cotype (cotype is for the interaction file only — the user-agent contract surface), so the original hash-based mechanism stays.
- **Test strategy:** Generate a `k4k`-owned KB file under `.k4k/`; user-edit it; run k4k; assert no regeneration and exactly one `ownership.flip` event.

### P15 — Pluggable backend conformance
- **Statement:** k4k works against any implementation of `Agent_backend` (resp. `Verifier`) that satisfies the contract in `spec/api-contracts.md`. Switching backends does not require code changes outside the backend module.
- **Violation:** Hardcoded `claude` invocation in the harness loop.
- **Why:** Architected for Ollama (and others) without v0 ship. See ADR-003.
- **Test strategy:** A test-only `Stub_agent` and `Stub_verifier`; the integration test suite runs entirely against them. Switching to `claude-code` requires only `--backend=claude-code`.

### P16 — Incremental, ownership-aware KB regeneration
- **Statement:** KB regeneration in `.k4k/` only rewrites files whose source-of-truth aspects changed *and* whose ownership is `k4k`. User-owned KB files are never regenerated.
- **Violation:** Full KB rewrite on every gap-step.
- **Why:** Cost (agent budget) and safety (user edits). See Q17b, Q17d, Q17f.
- **Test strategy:** Two-step run; assert only the affected KB files have new mtimes; user-edit one of them; re-run; assert it is unchanged.

### P17 — No agent judgment on validity
- **Statement:** No state transition of any property's `status` is gated on an agent's self-assessment. Only verifier output and human input drive transitions.
- **Violation:** A code path that reads "the agent says it's done" and marks the property `established`.
- **Why:** Determinism, auditability. The whole thesis of NOTES.md.
- **Test strategy:** Code-review check (literate comments must reference verifier evidence, not agent text); audit pass that searches for `agent.*ok`/`agent.*pass` patterns in conditionals.

### P18 — Two-run formalization minimum
- **Statement:** The semantic stability check runs the formalization at least twice; ambiguity is detected by canonical-hash inequality.
- **Violation:** A "fast path" that runs once and trusts the result.
- **Why:** A single stochastic run cannot detect ambiguity. See Q13a, ADR-005.
- **Test strategy:** Stub agent returns two non-equivalent ASTs; assert k4k reports unstable with divergence details.

### P19 — Stable-D caching by user-section hash
- **Statement:** If the user-owned sections of `<file.k4k>` are unchanged since the last successful stability run, the formalization pass is skipped.
- **Violation:** k4k re-runs formalization on every invocation despite no user edits.
- **Why:** Cost economy, especially under tight Ollama budgets. See Q13g.
- **Test strategy:** Run twice with no edits; assert exactly one formalization invocation in the JSONL log.

### P20 — Property reference in source
- **Statement:** Every public function in k4k carries an `@invariant P<n>` doc-comment if it participates in enforcing one.
- **Violation:** A function that flips an ownership flag has no `@invariant P14`.
- **Why:** Auditability and KB↔code traceability. Tooling-checkable.
- **Test strategy:** Lint pass that scans public function signatures and checks ratio against expected list (target ≥ 80% coverage of P-list).

## Agent notes

> **Adding a property:** add an entry here first, then write the test, then implement. Reverse order is a methodology bug.
>
> **Removing a property:** never silently. Mark with `status: deprecated`, link the ADR that justifies removal, keep the entry visible for one minor version.

## Related files

- `properties/non-functional.md` — measurable criteria (latency, memory, …)
- `properties/edge-cases.md` — boundary conditions T1..Tn
- `conventions/testing-strategy.md` — how P-properties are tested
- `spec/algorithms.md` — procedures these properties constrain
