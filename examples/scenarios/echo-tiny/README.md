# echo-tiny — runnable end-to-end scenario

A deliberately-small `.k4k` file you can copy into a fresh
tempdir and watch k4k drive end-to-end against a real agent
backend. Designed as the lowest-risk first-run target.

## Why this scenario

Real agent runs against a fresh project hit three classes of
failure: (a) unstable formalization (two LLM calls produce
non-canonical-equivalent ASTs); (b) the agent picks a toolchain it
can't actually drive; (c) gap-step diffs don't apply or don't pass
verification. `echo-tiny.k4k` minimizes all three:

- **Three short acceptance examples** (the minimum coverage
  requires; per `lib/coverage.ml`).
- **One refusing example** with one error tag — keeps the gap
  small (3-4 properties).
- **Goal text explicitly hints OCaml + dune + alcotest +
  `_verifier.sh`** — known-good toolchain that the agent can
  drive on first try; biases away from heroic Tier-A on Rocq.
- **Tier-C is suggested in the goal text** so the first tradeoff
  proposal arrives quickly and the user can sign off in one edit.

## Setup

```bash
# Build k4k and the bundled backend; puts both on $PATH.
cd /home/coder/workspace/k4k
dune build && dune install

# A fresh tempdir is the cleanest test surface.
WORKDIR=$(mktemp -d)
cp examples/scenarios/echo-tiny/echo-tiny.k4k "$WORKDIR/in.k4k"
cd "$WORKDIR"

# Initialize git (k4k will do this automatically if you skip).
git init -q && git config user.email you@x && git config user.name you
git add -A && git commit -q -m initial

# Make sure ANTHROPIC_API_KEY is set (or claude is logged in via
# subscription auth — check `claude --version` works).
```

## Run

```bash
k4k --exit-on-done in.k4k
```

`k4k` autodetects the bundled `claude_code_backend` on `$PATH`
and writes `.k4k/config.json` on first run. If autodetection
didn't find it, edit `.k4k/config.json` and set
`backend.command` to the path of your backend.

## Expected trajectory

Probability of first-try success against current frontier models
is realistically ~30-60%; this scenario is tuned to make it more
likely but still depends on the model. Most-likely event order:

```
watcher.start
agent.external_configured             # config picked up
stability.pass                         # echo-tiny.k4k is structurally OK
formalize.ok                           # two-run protocol converged
version.start (version 1)              # branch k4k/version/1 cut
gap-step.start P9b9f69b                # first property attempt
   ... maybe: gap-step.reject (no diff applied / verifier said unknown)
   ... maybe: gap-step.reject again, with the prior failure reason
   ... maybe: gap-step.tradeoff after 3 strikes
   ... if tradeoff: tradeoff.proposed → user replies inline
                    `Approved: Tier C` → tradeoff.approved
                    → drive_at_tier with Tier-C prompt
version.commit (× number_of_properties)
version.complete (tag = v1)
watcher.exit
```

What lands on disk:

```
in.k4k                                 # status block updated, breadcrumbs
src/<your-source>.ml                   # the implementation
test/<your-test>.ml                    # alcotest cases named P<id>_<slug>
dune-project, dune                      # build config
_verifier.sh                           # the wrapper, conformant to
                                        # kb/external/verifier-protocol.md
.k4k/log.jsonl                         # full event stream
.k4k/version/1/audit.md                # human-readable audit
git tag v1                             # annotated tag at the merge
```

## What can go wrong (most-frequent first)

- **`formalize.unstable`**: two LLM calls produced non-equivalent
  ASTs. A clarification is appended; check the in-file block,
  refine the goal text (e.g. tighten the joining-character /
  trailing-newline language), save the file. The watcher
  re-formalizes on the next stability tick.

- **`tradeoff.proposed` waiting on Tier-C sign-off**: the agent
  hit 3 Tier-A failures on a property. Open `in.k4k`, find the
  `## k4k:tradeoff:proposal:<ts>` block, write
  `Approved: Tier C` on a new line inside it, save. The watcher
  picks the reply up and retries at Tier C.

- **`version.unsatisfiable_streak`** (after 3 rolled-back versions
  in a row): the spec is likely too ambitious for the current
  backend. The escalation clarification lists three actions:
  refine the spec, accept a degraded tier, or switch to a
  stronger backend. Pick one, save the file, the watcher resumes.

- **`agent.tool_error` repeatedly**: the backend can't reach
  `claude`. Check `ANTHROPIC_API_KEY` / `claude --version`.

- **`agent.unconfigured`**: `K4K_BACKEND_COMMAND` is unset AND
  autodetection didn't find a backend. Edit `.k4k/config.json`
  manually and set `backend.command`.

## Stopping

Ctrl-C (cooperative shutdown ≤ 5s; NF1).

To abort an in-flight version cleanly, write `request: rollback`
in the `## k4k:status` block and save. The watcher tears down the
version branch and exits the loop.

## Cost expectation

A successful one-version run is typically 8-15 agent calls (2
formalize + 3-4 properties × 1-3 attempts each). On Claude Sonnet
~$0.05-0.30 per attempt-cycle. Multi-rollback recovery scales
linearly. The Ralph-budget escalation at 3 rollbacks gives you a
chance to step in before bills accumulate.
