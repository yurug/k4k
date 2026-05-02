---
id: domain.prd
type: spec
summary: v0 product scope for k4k — a deterministic harness that builds POSIX CLI programs from an interaction file via a coding-agent backend and a verifier.
domain: product
last-updated: 2026-05-02
depends-on: [glossary]
refines: []
related: [spec.api-contracts, spec.algorithms, properties.functional, properties.non-functional]
---

# Product Requirements — k4k v0

## One-liner

`k4k` is a deterministic harness that drives a coding agent to build a POSIX-like CLI program characterized by a user-edited interaction file, accepting only patches a verifier validates against a formal characterization derived from that file.

## Scope

This document is the *what* and *why* for v0. The *how* lives in `spec/`. Out-of-scope items at the bottom are commitments — adding any of them is a breaking change to v0's contract.

## Why this exists

The user has stated (in `kb/NOTES.md`) that coding agents are stochastic processes that converge to valid answers given a deterministic, efficient, complete harness. v0 is the smallest possible reification of that thesis: one agent backend, one verifier, one program class, end-to-end on a single toy example.

## Users

A single developer running on Linux x86_64 or macOS (Intel or ARM), comfortable with a shell, with API credentials for the agent backend in their environment, with the verifier toolchain installed (v0: `dune` + an OCaml compiler ≥ 5.1).

## User stories

### S1 — First spec, first run
> *As a developer, I write `myproject.k4k` describing what my CLI does, then run `k4k myproject.k4k`. If my spec is incomplete or ambiguous, k4k tells me precisely what's missing — by appending clarifying questions to the file. Once the spec is stable, k4k builds a working program in my current directory and reports `done`.*

### S2 — Iterative refinement
> *I add a new acceptance example to the interaction file mid-development. On the next `k4k` run, the new property appears in the gap, the harness drives it to `established`, and no previously-established property regresses.*

### S3 — Stuck spec
> *A property fails verification 3 times. k4k stops touching it, marks it `blocked`, appends a clarifying question to the interaction file, and exits with the property listed in the status output. I answer the question; the next run resumes.*

### S4 — Audit
> *I want to convince a reviewer that my CLI does what the spec says. I open `.k4k/reports/audit-<timestamp>.md` (one entry per established property + verifier evidence) and `.k4k/manifest.json` (hashes of every artefact). The audit is reproducible — re-running `k4k --check` on the same inputs yields the same gap.*

### S5 — Stability check
> *I want to validate my interaction file without spending agent budget. I run `k4k --check myproject.k4k` and see either `stable` or a precise list of issues.*

### S6 — Reset
> *Something is off and I want a fresh start. I run `k4k --reset myproject.k4k --yes`; `.k4k/` is wiped; the next `k4k` run rebuilds from scratch.*

## Command surface (v0)

| Command                          | Behavior                                                              |
|----------------------------------|-----------------------------------------------------------------------|
| `k4k <file.k4k>`                 | One full convergence pass: stability → gap → drive properties.        |
| `k4k --check <file.k4k>`         | Stability check only. No agent calls (uses cached `D` if available, else one formalization pass; never enters the gap-step loop). |
| `k4k --status <file.k4k>`        | Print current gap from `.k4k/`. No work, no agent calls.              |
| `k4k --reset <file.k4k> --yes`   | Wipe `.k4k/` for this project. `--yes` required to skip confirmation. |
| Flags: `-v`, `-vv`, `--no-color`, `--max-steps N` | Verbosity, color suppression, hard step cap.        |
| Flags: `--budget M`              | Hard budget cap in agent budget units (default 1000).                  |
| Flags: `--verifier CMD`          | Override the verifier command from the frontmatter.                    |
| Flags: `--verifier-timeout S`    | Override the verifier wall-clock timeout in seconds.                   |

Exit codes per `spec/error-taxonomy.md`.

## Non-functional expectations

### Determinism
For the same `(interaction file content, .k4k/ contents, agent backend version, verifier version)`, k4k always produces the same gap, the same per-property risk-score ranking, and the same exit code. Agent-produced patches *may* differ; their *acceptance* may not (the verifier is deterministic, so any patch that establishes the property is equally valid).

### Responsiveness
- Ctrl-C honored within ≤ 5 s (`P.responsiveness`, `properties/non-functional.md#NF1`).
- Default TTY output: one-line in-place status, never blocks waiting for I/O the user did not request.

### Budget bounds
- Soft cap 100 budget units / gap-step (configurable in interaction-file frontmatter).
- Hard cap 1000 budget units / invocation. Exceeding either: graceful exit with a remediation message; `.k4k/` left in a consistent state.

### Footprint
- v0 runs in the user's working directory with the user's privileges — no implicit sandboxing. Documented in `runbooks/security.md` (planned).
- All persistent state confined to `.k4k/`, `<file.k4k>` (read-write), and source files of the program being built.

## Constraints inherited from `kb/NOTES.md`

- The harness is **deterministic** (same observable behavior ⇒ same evaluation), **efficient** (each evaluation modifies the agent context to *reduce* the gap), **complete** (every aspect that matters is covered).
- Verifiable artefacts: the audit report (`reports/audit-<timestamp>.md`) and the manifest (`.k4k/manifest.json`) are sufficient to reconstruct the state of any decision k4k made.
- Model-agnostic: no agent's *judgment* validates anything. Verifier and human are the only judges.
- Class scope: POSIX-like CLIs (well-specified I/O, behavior fully determined by argv + filesystem).

## Out of scope for v0 (explicit commitments)

These are NOT in v0. Adding any of them means a v1+ release.

- GUI / TUI dashboards
- Multi-user / team / SaaS modes
- Agent backends beyond `claude-code` (Ollama is **architected for** but not shipped — see ADR-003)
- Verifiers beyond the `examples/verifiers/dune-ocaml/` reference (Rocq, Lean, Verus, Frama-C, AFL — none of these require k4k changes; users plug them in via the wire protocol per ADR-008)
- Custom DSL compilation or self-built verifiers
- Distributed or parallel gap-step execution
- Self-hosted model inference
- IDE integrations
- Program classes other than `cli` (no `library`, `filter`, …)
- Windows support
- Sandboxing of agent-written code (documented as user's responsibility)

## Success criteria for v0

The skill (`spec-driven-dev`) considers k4k v0 complete when:
1. A toy interaction file (e.g. "echo CLI that respects `--upper`") is driven from empty repo to passing-test green by `k4k`, end-to-end, in one invocation, on a Linux x86_64 dev machine.
2. The same run is reproducible: re-running `k4k --check` on the resulting `<file.k4k>` reports `stable`; re-running `k4k` reports `done` (gap empty).
3. `.k4k/manifest.json` and `reports/audit-*.md` are sufficient to reconstruct all decisions.
4. All P-properties in `properties/functional.md` are tested green; all NF-properties are measured within budget; all T-edge-cases are handled per spec.

## Agent notes

> The recursive nature is intentional: we are using a coding agent (Claude Code) to build a coding agent (k4k). The agentic-dev-kit methodology applies to building k4k itself; k4k embeds its own (smaller, more rigorous) methodology for building target programs. Don't conflate the two — `kb/` is for the meta level, `.k4k/` is for the object level.

## Related files

- `spec/algorithms.md` — the harness algorithm (stability, gap-step, risk-score, canonicalization)
- `spec/api-contracts.md` — agent backend & verifier interfaces
- `properties/functional.md` — P1..Pn invariants this PRD implies
- `architecture/overview.md` — module structure that realizes the command surface
