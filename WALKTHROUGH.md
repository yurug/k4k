# k4k — first-run walkthrough

What to expect from a clean repo to a verified version-1 program.

## Prerequisites

Verify these are on `$PATH`:

```bash
cotype --version   # ADR-010, file-concurrency primitive (pipx install cotype)
git --version      # ADR-013, version-as-branch
claude --version   # the agent backend (https://docs.claude.com)
```

If `ANTHROPIC_API_KEY` is set in your environment, the bundled
`claude-code` backend will use it. Otherwise it relies on whatever
auth `claude` is configured with.

## Build

```bash
cd /home/coder/workspace/k4k
dune build
# Optionally install on PATH; otherwise use absolute paths below.
# dune install
```

## Smoke 1 — wire-only, no API tokens

A fresh tempdir + a stable `.k4k` file + `--exit-on-stable`. The
watcher initializes, runs the structural-stability check, and exits.
No formalization, no agent calls.

```bash
WORKDIR=$(mktemp -d)
cd "$WORKDIR"
git init -q && git config user.email x@x && git config user.name x
cat > test.k4k <<'EOF'
---
k4k:
  version: 1
  class: cli
---
# echo --upper

## Goal
Echo argv with optional uppercasing.

## Inputs and outputs
- argv: positional args optionally preceded by `--upper`
- stdout: argv joined; uppercased iff `--upper` is set

## Error taxonomy
N/A

## File-system contract
N/A

## Concurrency
N/A

## Performance bounds
N/A

## Acceptance examples
1. argv=["hi"]            → "hi\n"
2. argv=["--upper","hi"]  → "HI\n"
3. argv=["a","b"]         → "a b\n"

## Refusing examples
1. argv=["--unknown"] → exit non-zero

## Out of scope
- everything except echoing
EOF
git add -A && git commit -q -m initial

/home/coder/workspace/k4k/_build/install/default/bin/k4k \
  --exit-on-stable test.k4k
```

Expected stdout (JSONL):

```
{"ts":"...","event":"watcher.start","details":{"file":"...test.k4k"}}
{"ts":"...","event":"agent.unconfigured","details":{"hint":"set K4K_BACKEND_COMMAND or K4K_STUB_RESPONSES"}}
{"ts":"...","event":"stability.pass","details":{}}
{"ts":"...","event":"watcher.exit","details":{}}
```

`stability.pass` confirms the structural check accepts the file.
`agent.unconfigured` is just a heads-up that no backend is wired —
fine for `--exit-on-stable`.

## Smoke 2 — full v1 development against real claude (consumes tokens)

```bash
# Same WORKDIR / test.k4k as above.
export K4K_BACKEND_COMMAND="/home/coder/workspace/k4k/_build/install/default/bin/claude_code_backend"

# --exit-on-done returns after the first version completes (Done) or
# rolls back. Without it the watcher polls forever.
/home/coder/workspace/k4k/_build/install/default/bin/k4k \
  --exit-on-done test.k4k
```

Expected JSONL trajectory (event names; details elided):

```
watcher.start
agent.external_configured            # K4K_BACKEND_COMMAND wired
stability.pass                        # structure is OK
formalize.ok                          # two-run formalization converged
                                       (or formalize.cached on a re-run)
version.start                         # k4k/version/1 branch cut
version.commit (× N)                  # one per established property
version.complete                      # merge to main, tag v1
watcher.exit
```

What lands on disk:

```
test.k4k                              # status block updated
.k4k/manifest.json                    # cached desired D
.k4k/log.jsonl                        # the JSONL stream above + per-step logs
.k4k/version/1/manifest.json          # frozen-at-tag-time per-version record
.k4k/version/1/D-spec.json            # canonicalized D
.k4k/version/1/audit.md               # human-readable audit
.k4k/agent-runs/<id>/                 # prompt + response + verdict per call
src/<...>                             # the agent's source code
_verifier.sh                          # the agent's verifier wrapper
git tag                               # v1, annotated
```

`git log --oneline` on `main` shows the merge from `k4k/version/1`
plus the per-property `[k4k] establish <pid>` commits.

## What can go wrong

- **`agent.unconfigured`** + nothing else: `K4K_BACKEND_COMMAND` is
  not set or empty. Set it.
- **`agent.tool_error`** repeatedly: the backend executable is
  failing (likely missing `claude` on `$PATH` or auth). Inspect
  `.k4k/agent-runs/<id>/verdict.json` for the wrapper's stderr.
- **`version.skip` with `reason: no-spec-change`**: idempotence
  gate — the previous completed version already converged at this
  exact D. Make a meaningful edit to the user-owned sections.
- **`formalize.unstable`** or **`formalize.coverage_unstable`**: the
  agent could not produce a stable D. A clarification block was
  appended; reply inline and re-save.
- **`tradeoff.proposed`**: Tier-A failed 3× on a property. The
  watcher pauses and waits for your reply (`Approved: Tier B|C` or
  `Rejected: <guidance>`) inside the proposal block. Edit and save.

## Stopping

The watcher is signal-driven. SIGINT (Ctrl-C) cancels cooperatively
within ~5s (NF1). SIGTERM is the same.

In-file directives stop a version cooperatively:

```
## k4k:status
- request: rollback   # aborts the in-flight version, leaves baseline intact
- request: pause      # halts the gap-step loop without reverting
```

## More

- Architecture: `kb/architecture/overview.md`
- All audit reports: `kb/reports/audit-2026-05-08-*`
- Test environment knobs: `kb/runbooks/test-environment.md`
