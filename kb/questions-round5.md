---
phase: 1-redux
round: 5
created: 2026-05-08
status: awaiting-user
follows: questions-round4.md
---

# k4k v2 — Round 5 Ambiguity Resolution

> **What round 4 settled**, and what shifted:
> - **B5 — backwards-compat with v0:** none required. The v0 surface was never used in the wild; we don't tolerate v0-shaped frontmatter or HTML ownership tags, we just delete them.
> - **E1/E2 — k4k does NOT hardcode a toolchain set.** The agent (running on a frontier model) picks the toolchain per project, and adapts. k4k transports that choice via the existing wire protocol. My round-4 default ("v2 ships Rocq + Frama-C") was reintroducing the kind of hardcoded tool-specific code ADR-008/009 deleted; retracted.
> - **E3 — multi-model backend awareness:** future, not v2 ship — but the architecture must accommodate it (frontier model for high-level proof structure; smaller models for technical lemma scripts; routing decisions made by k4k to optimize token spend).
> - **E5 — auto-install:** **k4k installs what's useful.** No user-facing "please run `opam install coq`" — k4k runs it itself. Boundary still TBD (this round, §K).
> - **I2 — Tier-C `dune-ocaml` example:** delete. Removes the temptation to default-fall-back to testing; clears the example-tree.
>
> **User-added questions** that need their own answers (this round, §M, §N): version-as-git-branch model, and how to keep the live `.k4k` file scannable as versions accumulate.
>
> Conventions: edit *Default* in place, override with `Answer:`, mark `TBD` if open. Tell me when done. This round is shorter than round 4 — only the residual items.

---

## § J. Agent-driven toolchain selection

If k4k doesn't pick the toolchain, but the agent does, the protocol layer needs to convey the choice cleanly.

**J1. How does the agent communicate its toolchain choice to k4k?**
Default: as part of the **formalization pass output**. The two-run formalization protocol (ADR-005) currently produces a canonical `D` (formal characterization). That output gains a top-level `verifier_command : list-of-string` and `language : string` field. The agent emits, e.g., `verifier_command: ["coqc"]`, `language: "rocq"`. The wire-protocol verifier executable is invoked with that command (no further selection logic in k4k). On gap-step prompts, k4k tells the agent "the project's toolchain is <language>; emit code/proofs in that language." Same shape for the implementation language (`extraction_target: "ocaml"` or "c", etc.).

**J2. What if the agent picks a toolchain k4k doesn't have wrappers for?**
Default: k4k doesn't have *wrappers* for any specific toolchain — it has the wire protocol (ADR-008). The wire is `<command> --workdir … --focus … --output …`. As long as the agent's chosen `verifier_command` is an executable that conforms to that protocol, k4k runs it. **For toolchains that don't natively conform** (i.e. running raw `coqc` doesn't speak the protocol), the agent is responsible for emitting **a thin wrapper script** alongside the project source — e.g. `proofs/verify.sh` — that translates between the protocol and the native tool. k4k still doesn't know about Rocq/Frama-C/etc.; it just runs whatever script the agent named.

**J3. The `examples/verifiers/dune-ocaml/` was a wrapper of exactly this shape (Tier-C, deleted per I2). Should we ship a Tier-A wrapper example?**
Default: **no — and this is consistent**. We deleted dune-ocaml so it doesn't tempt the agent toward Tier C; symmetrically, we don't ship a "canonical Rocq wrapper" because that would tempt the agent to use it instead of generating one tuned to the project. The agent's job is to write the wrapper from scratch, *for this project*, conforming to `kb/external/verifier-protocol.md`. The protocol doc itself is the only example the agent needs.

**J4. Tradeoff implications: when the agent proposes Tier B/C, does it also pick the toolchain for that tier?**
Default: yes. Tradeoff proposal (`## k4k:tradeoff:proposal:<ts>`) includes the agent's proposed toolchain for the degraded tier. E.g. "drop to Tier B; I propose: a Rocq specification of the termination predicate (proven), plus a hand-written OCaml implementation tested via qcheck against 10 000 randomized inputs and a 1-hour `afl-fuzz` campaign. Concretely: tooling is qcheck + afl-fuzz; verifier wrapper at `tier-b-verify.sh`."

---

## § K. Auto-installation of tooling

The user said k4k installs what's useful. Defining the boundary.

**K1. Which package managers does k4k invoke autonomously?**
Default: **user-scoped, no-sudo package managers only**. Specifically:
- `opam install <pkg>` (current switch, user's home; standard for OCaml tooling: dune, coq, frama-c, alt-ergo, etc.)
- `uv tool install <pkg>` or `pipx install <pkg>` (Python tools: cotype is already in this category)
- `npm install -g --prefix=$HOME/.local/share/k4k/npm` (when an agent picks JS-ecosystem tooling, contained to a k4k-managed prefix)
- `cargo install --locked` (Rust tooling: Verus and friends; user's `~/.cargo/bin`)

Anything requiring `sudo` or system package managers (`apt`, `dnf`, `brew`, `pacman`) is **NOT** auto-installed; k4k surfaces a clarification block: "I need `<pkg>` from `<system-pkg-manager>`. Either run `<command>` yourself, or tell me to proceed with a non-sudo workaround if one exists."

**K2. What about the user not having opam (or whichever underlying ecosystem manager)?**
Default: **k4k attempts to install the ecosystem manager itself** if it's missing AND the install path is user-scoped (e.g. opam's `bash <(curl ...)` install to `~/.opam`). For genuinely-unrecoverable cases (no compiler at all, no `curl`, no network), k4k surfaces a clarification with concrete `bash` commands the user can copy-paste.

**K3. Where does the install actually happen?**
Default: in the **user's home environment**, not in `.k4k/`. Rationale: tools installed for one project are useful for the next. Side-effect-tracking: each install emits a `tool.installed` JSONL event with package name + version + path; the audit trail in `.k4k/version/<n>/manifest.json` records which tool versions were used. If the user later cares to clean up, they can `opam uninstall` themselves.

**K4. When k4k upgrades a tool to satisfy a new project, does it confirm with the user first?**
Default: **upgrades require a clarification block** ("I need `coq ≥ 9.1`; you have `8.20.1`. Approve `opam upgrade coq` or tell me to use the older version with a Tier-A degradation proposal."). Fresh installs of new tools do NOT require confirmation — they're additive. Upgrades may break other projects, so they're consent-gated.

**K5. Network access during install?**
Default: **assumed available**. If an install fails because of network (offline, firewall, etc.), k4k surfaces a clarification with the failed command and stderr, asking the user to fix or proceed with a degradation. k4k does NOT mirror packages or maintain a local cache beyond what the package manager itself provides.

---

## § L. Multi-model backend awareness

Forward-looking architectural prep — v2 ship, or just structural readiness?

**L1. Does v2 ship multi-model routing, or just the structural hooks?**
Default: **structural hooks only.** v2 ships a single backend per project (the agent), reading from `cotype` and producing prompts, but the `Backend_external` wire protocol gains a `--role <orchestrator|prover|implementer|reviewer>` argument that the configured backend may ignore (single-model setups) or use (future multi-model setups that route per role). Routing logic itself is v3+.

**L2. How is the role chosen for a given agent call?**
Default: in the **prompt-composition layer** (`lib/Prompts`). For v2: every call passes `--role orchestrator` (the same model handles everything). For v3: per-purpose mapping (e.g. `formalization → orchestrator`, `gap-step proof skeleton → prover`, `gap-step technical lemma → implementer`). The mapping itself becomes a `kb/external/role-routing.md` config in v3+; v2 just hardcodes `orchestrator`.

**L3. Token-cost optimization beyond role routing?**
Default: out of scope for v2. Tracked in the JSONL log (`agent.invoke.budget_used`), surfaced in the audit trail. v3+ may add cost-aware routing.

---

## § M. Version-as-git-branch model

Your user-added question 1. The framing I had — `.k4k/version/<n>/` as a self-contained working copy — is wrong; using git branches is cleaner.

**M1. Does k4k assume the user's project is a git repository?**
Default: **yes, k4k requires `git` available and the project to be a git repo** (or auto-runs `git init` on first run if not). cotype already assumes a regular file under git's purview; this just makes the assumption explicit. The interaction file `myproject.k4k` and any source k4k generates live in this repo.

**M2. How are versions modeled in git?**
Default: **each version is a git branch** named `k4k/version/<n>`. When k4k starts version N:
1. The current `main` (or whatever the user's default branch is named) is the baseline.
2. k4k creates the branch `k4k/version/<n>` from that baseline.
3. Each accepted gap-step's patch is committed on that branch (one commit per accepted property, with messages like `[k4k] establish P_argv_handles_upper`).
4. On version completion, k4k **merges the branch into the user's default branch** (fast-forward when possible; otherwise via merge commit) and tags `v<n>`.
5. On rollback, the branch is deleted; default branch is unchanged.

The user's "release" workflow (publishing the source / packaging) is then standard: tag `v<n>` lives on the default branch with all accepted source. The user pushes, packages, distributes — k4k doesn't get involved.

**M3. What does `.k4k/version/<n>/` then contain?**
Default: **only audit/operational state**, never source. Layout:
```
.k4k/version/<n>/
  D-spec.json              # canonical AST, immutable post-stability
  tiers.json               # per-property tier assignments + sign-off references
  agent-runs/              # prompts + responses + verdicts (audit trail)
  verifier-runs/           # verifier output for each accepted property
  manifest.json            # tool versions, branch ref (k4k/version/<n>), tag (v<n>)
  audit.md                 # the human-readable per-property audit summary
```
Source — proofs, extracted code, hand-written code, ACSL annotations — lives **in the project's git tree** (e.g. `proofs/echo.v`, `src/echo/main.ml`), accessible as you'd expect on a regular git checkout. To inspect version N's source, the user does `git checkout v<n>` (or `git checkout k4k/version/<n>` if mid-development).

**M4. What happens if the user's git tree is dirty when k4k tries to start a version?**
Default: per the v0 `Git.is_clean` filter, `.k4k/`, `_build/`, `.<basename>.cotype/` are auto-ignored. Anything else dirty → k4k surfaces a clarification: "Your working tree has uncommitted changes in `<paths>`. I can't safely start version N; commit or stash first, or tell me `Approved: discard` to throw them away."

**M5. What if the user pushes/pulls/branches outside k4k mid-development?**
Default: k4k re-reads git state via `Git.is_clean` + `git rev-parse HEAD` on every gap-step. If the default branch moved underneath an in-flight version, k4k surfaces a clarification ("Your `main` was updated while I was developing version N. I can: rebase my branch onto the new `main`, or pause and let you reconcile manually. Reply.") The user is the source of truth for the git tree; k4k is a polite cooperating peer.

---

## § N. Keeping the live `.k4k` file scannable

Your user-added question 2. As versions accumulate, the file shouldn't bloat.

**N1. Pruning rules for resolved blocks.**
Default:
- `## k4k:clarification:<ts>` blocks: once the user has answered (i.e. the spec re-stabilizes after an edit), k4k **moves the block to `.k4k/version/<current>/clarifications/<ts>.md`** and replaces it in the file with a one-line breadcrumb: `<!-- k4k:clarification 2026-05-08-094200 — resolved; archived -->`. Breadcrumb is invisible in rendered Markdown.
- `## k4k:tradeoff:proposal:<ts>` blocks: same shape — once approved/rejected, archive to `.k4k/version/<current>/tradeoffs/<ts>.md`, leave a one-line breadcrumb.
- `## k4k:welcome` block: deleted entirely after first round of clarifications resolved (per round-4 B4).

**N2. Old `## k4k:version:<n>` blocks — keep, prune, or summarize?**
Default: **keep the most-recent N (default 3) version blocks in the file; older versions get summarized to one line.** E.g. once version 5 is in flight, versions 1–2 collapse to:
```markdown
## Past versions
- v1 (2026-05-02 → 2026-05-04): 12 properties · all Tier A · tag `v1`
- v2 (2026-05-04 → 2026-05-05): 14 properties · 12 Tier A, 2 Tier B · tag `v2`
```
Detailed version blocks for v3, v4, v5 stay in full. The `kept-versions: 3` is overridable via frontmatter `k4k.live_versions_in_file: <n>`.

**N3. Status block size.**
Default: bounded — at most 30 lines. If too much information accrues (long pending-edit list, lots of activity), k4k splits: top of status block is "current state (5 lines)"; rest behind a `<details>` HTML block (which Markdown viewers fold).

**N4. Where do users go for the full history?**
Default: `.k4k/HISTORY.md` — a single chronological log auto-maintained by k4k, listing every clarification, tradeoff, version transition, and rollback. Linked from the file's `## k4k:status` block. Users who want context dive in there. Users who want the live picture stay in the `.k4k` file.

---

## § User-added

(Add your own questions or override defaults in this section.)
