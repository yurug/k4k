---
id: runbooks.drift-watch
type: procedure
summary: Weekly maintenance: re-record dependency versions; run protocol-conformance suite; flag drift between `kb/external/*.md` contracts and the live versions.
domain: runbooks
last-updated: 2026-05-07
depends-on: [external.backend-protocol, external.verifier-protocol, external.cotype]
refines: []
related: [runbooks.audit-checklist]
---

# Drift Watch

## Why this exists

ADR-008/009/010 made k4k tool-agnostic by construction — adding new tools is zero k4k changes. **What can still break the system is drift in the contracts**, not new tools:

1. `lib/{Backend,Verifier}_external` evolves and silently tightens the wire protocol → third-party tools that were conformant yesterday are no longer.
2. `cotype`, `git`, or the example-targeted tools (`dune`, `claude`, `ollama`) bump versions and change observable behavior → `kb/external/*.md` becomes a lie.
3. The reference examples in `examples/` rot — someone changes the wire-protocol parser without re-testing the examples.

Drift watch is the cadenced check that catches all three. It is not part of CI (nothing here gates a merge); it's a weekly hygiene pass that produces a report and flags issues for the maintainer.

## What to do (weekly cadence)

### 1. Re-build and run the conformance suite

```bash
cd /home/coder/workspace/k4k
dune build @check
dune runtest test/conformance --force
```

The suite at `test/conformance/test_conformance.ml` validates that every example binary in `examples/{backends,verifiers}/` emits JSON matching the documented schemas in `kb/external/{backend,verifier}-protocol.md`. **Six tests, all `Quick`.** Failure here is a real drift bug: either the example or the spec moved without the other.

### 2. Re-record dependency versions

```bash
bash scripts/record-dep-versions.sh > kb/reports/dep-versions-$(date +%Y-%m-%d).txt
```

The script (see below) probes every dep documented in `kb/external/*.md` and writes `<tool>: <version>` lines. Compare to the most recent prior report; flag any major-version change for follow-up.

### 3. Spot-check the KB against reality

For each tool in `kb/external/*.md`:
- Does the documented CLI shape (`<tool> --flag`) still match `<tool> --help`?
- Does the documented JSON envelope still match a sample invocation's output?
- Are exit codes still as documented?

This is manual; budget ~15 minutes per tool. The KB is the spec; reality is the implementation. When they diverge, the KB wins by default — open an issue describing the divergence and decide whether to update the KB (the dep changed) or report the dep upstream (the dep regressed).

### 4. Run the full test suite

```bash
dune runtest --force
```

207+ tests; should be all green. A failure that wasn't a drift-watch finding (i.e. unrelated to deps or examples) is a separate concern — file a bug.

### 5. Optional: live-mode smoke

If credentials and network allow:

```bash
K4K_LIVE=1 dune runtest test/integration --force 2>&1 | tail
```

Exercises real `claude` and real `ollama` (when configured). Skipped by default in CI; useful here to confirm the live backends still behave per spec.

## Failure modes and what they mean

| Conformance test fails | What broke | Action |
|---|---|---|
| `backend_protocol/*` | `examples/backends/<x>/main.ml` output diverged from spec, OR `kb/external/backend-protocol.md` changed without updating examples | Diff the two; correct whichever is stale; update the conformance test if the protocol genuinely evolved (with a `k4k.version` bump) |
| `verifier_protocol/*` | Same for verifiers | Same |
| Schema validator rejects a real-binary output | `lib/{Backend,Verifier}_external_parse` got stricter than the spec | Loosen the parser, or update the spec |

| Dep-version delta | What it implies |
|---|---|
| `cotype` minor/patch bump | Usually safe; verify the documented CLI commands and JSON envelope are unchanged. Run conformance suite. |
| `cotype` major bump | Read its release notes; expect breaking changes. Plan a coordinated `kb/external/cotype.md` + `lib/cotype.ml` update. |
| `git` major bump | Inspect `git status --porcelain` output shape; the `Git.is_clean` filter assumes line-prefix structure. |
| `dune` major bump | Check whether `dune build @runtest --display=quiet --root` flags still behave; alcotest line shape via `external/dune.md` was already an empirical fact. |
| `claude` / `ollama` bump | Backend examples may need adjustment; conformance suite catches schema drift. |

## Output

After each weekly pass, write a short report at `kb/reports/drift-watch-YYYY-MM-DD.md`:

```markdown
---
runbook: drift-watch
timestamp: <iso>
result: clean | drift-found
---

# Drift Watch — <date>

## Conformance suite
N/N green.

## Dep versions
| tool | recorded | previous | delta |
| cotype | 0.2.3 | 0.2.3 | none |
| ...

## KB spot-checks
- backend-protocol.md: <status>
- verifier-protocol.md: <status>
- cotype.md: <status>

## Open items
(none / or list)
```

`drift-found` results trigger an issue for the maintainer; `clean` results are filed for traceability.

## Scheduling

Manual: run weekly. Automated: a `schedule`d remote agent or a cron job on a developer machine. The runbook is short enough that a human can do it in 30 minutes; automation is a polish item.

## Agent notes

> **Drift watch is about the contracts, not the tools.** Adding Rocq, Lean, OpenAI, etc. is zero k4k changes (per ADR-008/009). What weekly drift watch protects is the *invariant that those zero-change paths keep working*.

## Related files

- `kb/external/backend-protocol.md` — the contract enforced for backends
- `kb/external/verifier-protocol.md` — the contract enforced for verifiers
- `kb/external/cotype.md` — the runtime contract for the cotype dep
- `test/conformance/test_conformance.ml` — the conformance suite this runbook invokes
- `scripts/record-dep-versions.sh` — the version recorder
