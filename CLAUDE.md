# k4k — Project Instructions for Claude Code

This project follows **Spec-Driven Agentic Development** (see `agentic-dev-kit/methodology/spec-driven-development.md`). The knowledge base in `kb/` is the **source of truth**. If you are starting work in this repo, read `kb/INDEX.md` first.

## What this project is

`k4k` (KISS for KISS) is a coding agent that builds POSIX-like CLI programs. It is itself meant to be KISS: behavior fully determined by CLI args + filesystem contents + explicit calls to a coding-agent backend and a verifier. The core idea is a *deterministic harness* that closes the gap between a desired characterization (`D`, derived from a user's interaction file) and the current state (`S`, derived from running a verifier on the source). See `kb/NOTES.md` for the founding vision and `kb/domain/prd.md` for the v0 scope.

## Core principles (non-negotiable)

1. **Spec before code.** Resolve ambiguities, write the KB, then implement. The KB is `kb/`; the per-target KB k4k *generates* lives in `.k4k/` of each target project.
2. **Fix the harness, not the output.** When the agent produces wrong code, improve the spec / properties / prompts in `kb/`, not the patch.
3. **No agent judgment on validity.** Only the verifier and the human accept properties. Agents propose patches; the harness accepts or rejects.
4. **Determinism on canonical AST.** Agents are stochastic; the harness's determinism contract holds on the canonicalized formal characterization, not on raw agent output. See `kb/architecture/decisions/adr-005-canonical-ast.md`.
5. **Optimize for the weakest supported backend.** Prompts and KB chunks must work on a small local Ollama model, not just on Claude Opus. Context economy is a first-class design constraint, not a v1 polish item. See `kb/conventions/context-economy.md`.
6. **Two-layer KB.** `kb/` describes `k4k` itself. `.k4k/` (in target projects) describes the program k4k is currently building. Don't conflate.
7. **File ownership is sacred.** User-owned sections in `.k4k`-files and KB files are never overwritten by k4k without `--force-reclaim`. Same model applies inside this repo's `kb/` for any file we mark `owner: user`.

## How to navigate this KB

Always start with `kb/INDEX.md`. Then follow `kb/indexes/by-task.md` for your task. Don't browse folders — the indexes are the navigation layer.

## When something is wrong

If the code contradicts the KB, the KB wins by default — open a PR fixing the code. If the KB is genuinely outdated, fix the KB *first*, then fix the code. Never patch in silence.

## Methodology phases (where in the process are we?)

- Phase 1 (ambiguity resolution) — done. See `kb/questions-round1.md`, `kb/questions-round2.md`.
- Phase 2 (KB construction) — in progress.
- Phase 3+ (plan, implement, audit) — not started.
