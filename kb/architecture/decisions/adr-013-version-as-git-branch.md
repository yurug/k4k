---
id: adr-013
type: decision
summary: Each k4k version is a git branch (`k4k/version/<n>`) of the user's project repo. Accepted gap-steps commit to the branch; on version completion k4k merges into the user's default branch and tags `v<n>`. Rollback deletes the branch. `.k4k/version/<n>/` carries audit-only state (no source).
domain: architecture
last-updated: 2026-05-08
depends-on: [adr-006, adr-007, adr-010, adr-011]
refines: []
related: [adr-011, adr-012]
---

# ADR-013: Versions are git branches

## Status
Accepted (2026-05-08). Refines ADR-006 (two-layer KB): clarifies that `.k4k/version/<n>/` carries audit-only state, not source. Pairs with ADR-011 (which introduced the version concept) and ADR-012 (which puts the source in the project tree).

## Context

Round-4 of v2 left `.k4k/version/<n>/` ambiguous — was it (a) an audit trail, (b) a self-contained working copy of the project at version N, or (c) both? The user's round-5 user-added question 1 surfaced the right framing:

> "Is it to be considered as a working copy for the development of version `<n>`, a bit like a git branch used during the development? If so, I assume that when the version development is completed, the source code will be pushed to the main branch repository for artefact distribution? I would find this meaningful: essentially we have a monorepository for development that contains repositories used for publication of source file and distribution of packages in the standard way it is done today in the industry."

This is exactly right. The user's project is a regular git repo. Versions are git branches. On completion, the branch merges to the default branch and gets a `v<n>` tag — standard industry practice. `.k4k/version/<n>/` is audit-only metadata about how that version was developed, not a parallel source tree.

## Decision

### 1. The user's project is a git repository

`k4k <file>` requires the project to be a git repo. If the project directory is not yet a git repo, k4k auto-runs `git init` on first launch (with a default branch of `main` if the user hasn't set `init.defaultBranch`). The interaction file `myproject.k4k` and any source k4k generates live in this repo.

### 2. Each k4k version is a git branch

When k4k starts version N (the moment a stable spec is snapshotted):

1. The current default branch (typically `main`) is the *baseline*. k4k records its commit SHA in `.k4k/version/<n>/manifest.json`.
2. k4k creates branch `k4k/version/<n>` from the baseline. All in-flight development happens on this branch.
3. Each accepted gap-step's patch is committed to `k4k/version/<n>` with a message of the form `[k4k] <verb> <property-id>` (e.g. `[k4k] establish P_argv_handles_upper`).
4. Wrapper scripts (e.g. `proofs/verify.sh` per ADR-012) are committed alongside source.
5. On version completion (gap empty under per-property tier assignments), k4k:
   - Merges `k4k/version/<n>` into the default branch (fast-forward when possible; otherwise via merge commit with a message `[k4k] merge version <n>`).
   - Tags the merge point `v<n>` (annotated tag with the version block's metadata as the message).
   - Optionally deletes the `k4k/version/<n>` branch (configurable via frontmatter `k4k.keep_version_branches: true`; default `false` — clean up after merge).
6. On rollback (`request: rollback`), k4k discards the `k4k/version/<n>` branch (`git branch -D`); default branch is unchanged.
7. On pause (`request: pause`), the branch stays in flight; k4k stops the gap-step loop until pause is lifted.

### 3. `.k4k/version/<n>/` is audit-only

The directory carries metadata, not source:

```
.k4k/version/<n>/
  D-spec.json              # canonical AST, immutable post-stability
  tiers.json               # per-property tier assignments + sign-off references
  agent-runs/<id>/         # prompts + responses + verdicts
    prompt.md
    response.md
    verdict.json
  verifier-runs/<id>/      # verifier output for each accepted property
    stdout.log
    stderr.log
    result.json
  clarifications/<ts>.md   # archived clarification blocks (post-resolution)
  tradeoffs/<ts>.md        # archived tradeoff proposals (post-sign-off)
  manifest.json            # tool versions; baseline-commit SHA;
                           # branch ref (k4k/version/<n>); tag (v<n>)
  audit.md                 # human-readable per-property audit summary
```

Source — proofs, extracted code, hand-written code, ACSL annotations, the wrapper script — lives **in the project's git tree**. To inspect version N's source, the user does `git checkout v<n>` (or `git checkout k4k/version/<n>` while in flight). To diff between versions: standard `git diff v1 v2`.

### 4. k4k cooperates with user-side git operations

The user may push, pull, branch, and otherwise operate on the git repo while k4k is watching. k4k re-reads git state (`Git.is_clean`, `git rev-parse HEAD`) on every gap-step and:

- If the working tree becomes dirty mid-development (the user committed something to `k4k/version/<n>` directly, or stashed changes that don't apply cleanly): pause and surface a clarification.
- If the default branch moved (user pulled new commits onto `main` while k4k was developing on `k4k/version/<n>`): surface a clarification asking whether to rebase the in-flight branch onto the new `main` or pause for the user to reconcile.
- If the user force-pushes / rewrites the branch k4k is on: pause and surface (`request: rollback` is the recommended recovery).

k4k is a polite cooperating peer with respect to git, not the owner. The user remains the source of truth for the repo's history.

### 5. The `Git.is_clean` filter remains

`.k4k/`, `_build/`, `.<basename>.cotype/` are auto-ignored as before (the post-Phase-7 + post-ADR-010 filter). `git/version/<n>` branches are not "dirty paths" — they're proper branches the user can see.

## Consequences

**Wins:**
- Standard industry workflow: the user's repo looks normal; versions are tags; the source is in the obvious place. No parallel-tree weirdness.
- Distribution / publication is the user's standard process: `git push --tags`, package publication from `v<n>` etc. k4k doesn't intermediate.
- `git diff v1 v2` is the natural way to see what changed between versions. Rollback is `git branch -D` — familiar primitive, easy to inspect.
- `.k4k/` shrinks: only audit metadata, not source mirrors.

**Costs:**
- k4k now has a hard dependency on `git` (already de facto since v0; now formalized).
- Auto-`git init` on first run is a side effect outside the `.k4k/` directory — subtle but acceptable per the autonomous-agent UX.
- User-side git operations (force-pushes, rebase of k4k branches, etc.) introduce surfacable race conditions that k4k must detect and surface as clarifications. Several new T-edge-cases: T-git-default-moved, T-git-force-push, T-git-dirty-mid-version.
- Merging `k4k/version/<n>` to `main` may produce a non-fast-forward merge commit with `[k4k]` authorship — visible in the user's git log. Documented; some users may want squash-merge instead. v2 default is regular merge; squash configurable later if needed.

**Out of scope for v2:**
- Worktrees instead of branches (cleaner for parallel development but more setup; defer).
- Auto-publishing tags to remotes (the user's `git push` is theirs to run).
- Multi-repo developments (e.g. the project depends on a sibling library k4k also builds). Future work.

## What this means for implementers

- **`bin/main.ml` startup** runs `git rev-parse --is-inside-work-tree`; on failure, runs `git init`. Honors any pre-existing default branch name.
- **`lib/Version` (new) + `lib/Git`** coordinate. `Version.start_new` does the branch creation; `Version.complete` does the merge + tag; `Version.rollback` deletes the branch.
- **Gap-step accept** commits to the in-flight branch with the `[k4k] establish <property>` message format. Crash mid-commit is recoverable: incomplete commits aren't visible to git.
- **The clean-tree filter** stays as-is. New edge cases (force-pushes, rebase) extend `properties/edge-cases.md` and surface as clarifications in the file, not as exit codes.
- **The default behavior on version completion is `merge --no-ff` + `tag -a v<n>`** unless the merge can fast-forward (in which case fast-forward is fine). Squash-merge is a v3+ option.
- **Branch cleanup post-merge** is the default (`k4k.keep_version_branches: false`); audit trail in `.k4k/version/<n>/` preserves the branch's commit history if anyone wants to reconstruct.

## Relationship to ADR-006 / ADR-010

ADR-006 (two-layer KB) said the target program's KB lives in `.k4k/`. ADR-013 clarifies: the *source* lives in the user's git tree; `.k4k/<derived-kb-files>` continue to live under `.k4k/` and are derived from the source + characterization. The two-layer KB framing stands; ADR-013 just constrains where the *source* in the second layer is materialized (the git tree, not `.k4k/`).

ADR-010 (cotype delegation) covers the interaction-file concurrency. The `.k4k` file lives at the root of the user's git repo (typical), and is one of the tracked files. cotype's sidecar `.<basename>.cotype/` is `.gitignore`d (added to the gitignore filter; same as `.k4k/`).
