---
id: adr-011
type: decision
summary: k4k v2 is an autonomous coding agent. The user's only interaction is writing prose in a single `.k4k` file via cotype. k4k watches the file, refines the spec via in-line clarifications, snapshots versions when stable, and develops + verifies in full autonomy with full formal verification by default.
domain: architecture
last-updated: 2026-05-08
depends-on: [adr-002, adr-005, adr-006, adr-008, adr-009, adr-010]
refines: [adr-002]
related: [adr-012, adr-013]
---

# ADR-011: Autonomous-agent UX + verification-tier hierarchy

## Status
Accepted (2026-05-08). Supersedes the v0/v1 developer-CLI framing wholesale (archived in `kb/archive/v0-drifted/`). The architectural commitments from ADR-005/006/008/009/010 stand unchanged; ADR-002's HTML-tag mechanism stays superseded; ADR-007's deterministic kb-regen stays the v0/v2 default with the agent-driven path still wired-but-inactive. Two follow-on ADRs (ADR-012, ADR-013) handle the toolchain and git-branch concerns introduced by this reorientation.

## Context

The v0/v1 build shipped a developer-CLI tool — `k4k` with flags (`--check`, `--status`, `--reset`, `--max-steps`, `--budget`, `--verifier`, `--backend`), YAML frontmatter exposing `k4k.backend.command` and `k4k.verifier.command` to the user, and a baseline verification tier of "alcotest tests run by `dune build @runtest`". The user's feedback (`kb/archive/v0-drifted/feedback-from-user-2026-05-08.md`) clarified two principles that reshape the product:

1. **The user only writes in the `.k4k` file.** No flags, no commands, no tooling configuration in frontmatter, no other files to maintain. The user's contract is: free-form prose describing what they want the program to do. Everything else flows through the same file via cotype.

2. **The verification baseline is full formal verification.** Implementations are extracted from / machine-checked against formal artifacts (Rocq + Extraction; Frama-C/ACSL+WP; Lean; Verus; F*). Testing-only verification is a degraded tier that requires the user's explicit in-file sign-off with k4k's written rationale.

These two principles together imply k4k is an *autonomous coding agent*, not a developer-operated tool. The user becomes the spec author; k4k becomes the implementation-and-verification author. They cooperate through the file.

## Decision

### 1. The user-facing surface is the `.k4k` file. Period.

The single CLI invocation `k4k <file>` starts a watcher process. Thereafter, the user's only interaction with k4k is editing the `.k4k` file via cotype. There are no flags, no subcommands, no other configuration mechanisms. The watcher process emits structured JSONL on stdout for operators (people debugging k4k itself); end users do not read stdout.

Operator-only flags `-v` / `-vv` exist but are not part of the user UX.

### 2. Watcher process model

`k4k <file>` is a foreground process. It polls cotype at 2 Hz (every 500 ms) checking for user edits, version-state transitions, and signal flags. The user wraps it in their own service manager (`tmux`, `nohup`, `systemd --user`) if they want it backgrounded — k4k does not daemonize.

A single watcher per file is enforced via `.k4k/watcher.pid`. Crash recovery: state is fully persisted in `.k4k/`, so a fresh `k4k <file>` invocation reads `manifest.json`, identifies any in-flight version, and resumes from the last completed gap-step. In-flight unaccepted patches are discarded (preserves P5 non-regression).

### 3. First-run UX

`k4k <file>` on a non-existent file creates the file with a starter template — frontmatter, required-section headings, and a `## How to use this file` block explaining the protocol. The user has nothing to know about YAML or about which sections to write; everything they need is in the template.

Prose-only files (no frontmatter) get auto-frontmatter inserted on first cotype save (`k4k.version: 1`, `class: cli`). If k4k cannot infer the class (the prose suggests a library, GUI, daemon — out of v2 scope), it surfaces a clarification asking the user.

A `## k4k:welcome` section explains the protocol on first run; auto-deletes after the user has answered the first round of clarifications.

### 4. Verification-tier hierarchy

Three tiers, applied **per property** (not per program):

- **Tier A — Full formal verification.** Implementation is extracted from / machine-checked against a formal artifact. The verifier runs `coqc` / `frama-c -wp` / `verus` / `lean` / etc. (whichever tooling the agent chose for this project — see ADR-012) and maps theorem-or-contract statuses to property statuses. **This is the default; it is what k4k aims for on every property.**

- **Tier B — Formal model + intensive testing.** A formal model exists; the implementation is hand-written and tested against the model via property-based testing + fuzzing. **Requires explicit user sign-off** in the `.k4k` file with k4k's written rationale.

- **Tier C — Testing-only.** No formal artifact. Tests + property-based tests + fuzzing alone. **Requires sign-off** AND explicit acknowledgment that the formal-correctness goal is forfeited for the relevant property. v2 ships *no* Tier-C reference example (the v1 `examples/verifiers/dune-ocaml/` is deleted — keeping it tempts the agent to default to Tier C; per round-5 I2).

A program can mix tiers: 10/12 properties at Tier A, 2/12 at Tier B is a valid version. The version block records the distribution.

### 5. In-file control surface

Four k4k-managed Markdown section patterns. The user reads them; the user does NOT edit them except for documented control directives. cotype's 3-way merge protects everything else.

- **`## k4k:status`** — live status. State, ETA, tier distribution, pending user edits, last activity, and a "User control directives" sub-section where the user writes `request: rollback` or `request: pause`. Fully replaced by k4k on every state transition (~every 30 s during development).

- **`## k4k:version:<n>`** — per-version snapshot. Hash of the canonical `D`, stabilization timestamp, property count, tier distribution, completion state, link to audit artefacts in `.k4k/version/<n>/`. Versions accumulate; old ones summarize to one line after 3 versions (configurable).

- **`## k4k:clarification:<ts>`** — questions when the spec is unstable. The user answers by editing the relevant *user-owned* sections directly; k4k re-reads on next cotype save. Resolved blocks are archived to `.k4k/version/<current>/clarifications/<ts>.md` with a one-line HTML-comment breadcrumb left in the file.

- **`## k4k:tradeoff:proposal:<ts>`** — Tier-A→B/C proposals. Property name, why Tier A failed, proposed degradation, what's lost, what's gained. The user replies inline: `Approved: Tier B` / `Rejected: <guidance>`. Resolved blocks archived to `.k4k/version/<current>/tradeoffs/<ts>.md`.

Only one open tradeoff proposal at a time — additional Tier-A failures queue, surfaced as a counter in the status block.

### 6. Version lifecycle

```
Drafting → Refining ⇄ Stable → Developing → [Awaiting-Tradeoff] → Developing → Done
                       ↑               ↓
                       └── Paused-Unknown-Unknown
                       └── Rolled-Back
```

**User edits during `Developing` queue for version N+1**, do not interrupt version N. Rollback (`request: rollback`) aborts the in-flight version. Pause (`request: pause`) halts the gap-step loop without reverting source. See ADR-013 for the git-branch implementation.

### 7. File scannability — pruning rules

To keep the live `.k4k` from ballooning over time:
- Resolved clarifications and tradeoffs archive to `.k4k/version/<n>/{clarifications,tradeoffs}/<ts>.md`; an HTML-comment breadcrumb stays in the file.
- The `## k4k:welcome` block deletes after the first clarification round resolves.
- Version blocks: most-recent 3 stay in full; older ones summarize to a single line under `## Past versions` (overridable via `k4k.live_versions_in_file: <n>` frontmatter).
- Status block bounded to ~30 lines; deeper detail behind a `<details>` HTML block.
- A separate auto-maintained `.k4k/HISTORY.md` carries the full chronological log (clarifications, tradeoffs, version transitions, rollbacks).

### 8. Multi-model backend awareness (structural-only in v2)

The `Backend_external` wire protocol gains a `--role <orchestrator|prover|implementer|reviewer>` argument. v2 always passes `orchestrator`; the backend may ignore it. v3+ may add per-purpose role routing (frontier model for proof structure; smaller models for technical lemma scripts; cost-aware decisions). Documented in `kb/external/backend-protocol.md`.

## Consequences

**Wins:**
- The user's mental model collapses to "I write what I want; the file does the rest." No vocabulary about toolchains, no flag memorization.
- The verification baseline shifts to formal verification; testing degrades only with explicit consent and rationale. The product's correctness story aligns with `kb/NOTES.md`'s "fully certified implementations" goal.
- The architectural commitments earned across v0/v1 (cotype, wire protocols, canonical AST, two-layer KB, deterministic kb-regen) all survive — they're correct under the new framing too. Engine code in `lib/` is largely intact.

**Costs:**
- Substantial wrapper rewrite: `bin/main.ml` becomes a watcher daemon; the v0 CLI flags vanish. The v0 CLI-specific tests delete with the code they exercised.
- The dune-ocaml example deletes (per round-5 I2). Conformance suite needs a new fixture.
- Three follow-on ADRs (ADR-012 agent-driven toolchain selection; ADR-013 version-as-git-branch) carry the operational details out of this ADR for clarity.
- The PRD, README, INDEX, several spec files were rewritten in the v2-cleanup commit (`f47ebbb`); this ADR + ADR-012/013 may require further sweeps as the commitments crystallize.

**Migration story:**
- v0/v1 `.k4k` files are not supported. The v0 fixture (`tests/fixtures/echo-upper.k4k`) gets rewritten to the v2 shape; the v0 form is preserved at `kb/archive/v0-drifted/echo-upper-v0.k4k` for reference.

## What this means for implementers

- **`bin/main.ml` is a watcher.** Polls cotype at 2 Hz; reads via `cotype open` → `base_path` (never directly); writes via `cotype save --base-sha` per ADR-010. Single-instance enforced via PID file. Foreground; no daemonization.
- **No user-facing CLI flags.** `-v`/`-vv` accepted for operators only. Anything else is drift.
- **Frontmatter is `version` + `class` only.** Tooling configuration moves into the formalization output (per ADR-012) — invisible to the user.
- **The v0 ad-hoc gap-step loop becomes a tier-aware loop.** Default is Tier A: agent emits proofs (in whatever language the agent chose for this project) + a wrapper script that conforms to `kb/external/verifier-protocol.md`. See ADR-012.
- **Versions are git branches** (ADR-013). `.k4k/version/<n>/` is audit-only, not source.
- **Tier-A failures open one tradeoff proposal at a time.** Pre-judgment is forbidden — k4k attempts Tier A first; only on attempt-and-time-out does it propose degradation.

## Relationship to NOTES.md and the v0 ADRs

- **`kb/NOTES.md`'s vision** of "deterministic harness driving stochastic agents to converge to valid answers" was always right at the engine layer. The v0 wrapper was wrong; v2 corrects the wrapper. The engine continues to do exactly what NOTES.md describes.
- **ADR-002 (interaction file format)** is now in its third revision: HTML ownership tags removed (ADR-010), tooling-frontmatter removed (this ADR), four k4k-managed section patterns codified (this ADR).
- **ADR-008/009 (wire-protocol verifier/backend)** are reinforced. v2 ships no built-in toolchain knowledge; the protocols are now even more central than in v1.
- **ADR-010 (cotype delegation)** is the single point of contact between user and agent. v2's entire UX flows through it.
