---
phase: 3
round: 3
created: 2026-05-02
status: awaiting-user
follows: questions-round2.md, kb/plan.md, kb/reports/plan-simulation-2026-05-02.md
---

# k4k — Round 3 Ambiguity Resolution (post-plan-simulation)

> **Why a round 3?**
> The Phase-3 plan-simulation gate (`kb/reports/plan-simulation-2026-05-02.md`) walked the 4-step implementation plan end-to-end and surfaced 4 genuine gaps that the implementer would otherwise have to invent answers for. One real KB contradiction was found and fixed in place (`T18` ownership-flip persistence). All other simulator-flagged items resolved against existing KB content.
>
> Same conventions: edit *Default* lines or replace with `Answer:`. Tell me to proceed when done.

---

## § Q3.1 — Prompt template location and templating syntax

**Where do `prompts/formalize.md`, `prompts/gap-step.md`, `prompts/kb-regen.md` live, and how are they templated?**

Default:
- They live in **`prompts/` at the root of the k4k repo**, not under `.k4k/`. They are part of the k4k binary's behavior, versioned with the source.
- They are **plain Markdown** with `{{var}}` placeholder substitution (no Mustache logic, no conditionals). The substitution is a pure string replacement keyed on a fixed set of variable names per template.
- They are **not target-customizable in v0**. Customization (per-target prompt overrides) is v1+.
- They are subject to all rules in `conventions/context-economy.md`; CI lint-checks token count and schema flatness.
- Each prompt's variables are declared in a YAML frontmatter block at the top of the prompt file:
  ```
  ---
  vars: [user_sections, example_input, example_output]
  ---
  ```

---

## § Q3.2 — Scratch git branch naming and lifecycle

**How are scratch branches named, cleaned up, and what happens on conflict?**

Default:
- **Naming:** `k4k/gap/<property-id>/<short-timestamp>` where short-timestamp is `YYYYMMDD-HHMMSS-<6char-rand>`. Slashes are valid in git branch names; the prefix `k4k/gap/` makes scratch branches trivially identifiable and `gitignore`-pattern-able.
- **Lifecycle:** Created at the start of `Gap_step.step`. Deleted via `git branch -D` on either (a) successful merge into the current branch, or (b) any failure path (rejected patch, SIGINT, exception). The deletion path is a `Stdlib.at_exit` registration so it runs even on uncaught panics.
- **Pre-existing branch with same name:** `k4k` aborts the gap-step with `ESTATE_CORRUPT` (exit 5). Recovery message points to `git branch --list 'k4k/gap/*'` to inspect, and `--reset` (which adds branch cleanup to its scope).
- **Working tree cleanliness pre-condition:** `Gap_step` requires a clean working tree (no uncommitted changes). If dirty, exit 5 with a message naming the dirty paths.

---

## § Q3.3 — `Backend_stub` canned-patch model

**How does `Backend_stub` produce deterministic responses for tests?**

Default:
- **Configuration shape:** `Backend_stub.create ~responses` where `responses : (purpose * trigger * response) list`.
  - `purpose : [`Formalization | `Gap_step | `Kb_regen]`
  - `trigger : prompt -> bool` (a predicate; usually `fun p -> String.is_substring p ~substring:"PXXX"` for a property-keyed match)
  - `response : (string, [ `Budget_exhausted | `Tool_error of string ]) result`
- **Lookup:** the first matching `(purpose, trigger)` wins. No match → `Tool_error "stub: no canned response for prompt"`.
- **Storage in tests:** responses are constructed inline in the test file (OCaml literals); not externalized to YAML/JSON. Rationale: keeps tests self-contained, type-checked, refactorable.
- **Diff format:** unified diff (`diff -u` style), compatible with `git apply`. The harness's diff applier uses `git apply --index`.
- **Weakness profile:** orthogonal to canned responses. `Backend_stub.create ~responses ~profile:`Weak applies post-processing to canned responses (truncation, JSON sloppiness injection, occasional refusal) per `conventions/context-economy.md`. v0 ships exactly two profiles: `` `Strong | `Weak ``.

---

## § Q3.4 — TTY status line format and `-v` interaction

**Exact format of the in-place TTY line; behavior under `-v` and `!isatty`.**

Default:
- **Default-verbosity TTY format** (single line, in-place via `\r` + ANSI clear-line):
  ```
  [k4k] step 3/12 • P3a4b1 (cli-rejects-empty-argv) • agent ████░░░░ • ETA 4m12s
  ```
  Components: `step <done>/<total>`; `<property-id> (<short-statement>)`; `agent <progress-bar>` (8 chars, advances during in-flight call, drains on completion); `ETA <wall-clock>`.
- **`-v` interaction:** `-v` *replaces* the in-place line with one line per state transition (parsed from JSONL events: `gap-step.start`, `gap-step.accept`, `gap-step.reject`, etc.) on stderr. The TTY line is suppressed. `-vv` adds tool-level diagnostics on stderr; the in-place line stays suppressed.
- **`!isatty(stdout)` (piped/redirected):** the in-place line is suppressed automatically; stdout receives one structured JSON object per state transition (mirroring `.k4k/log.jsonl`), so downstream tools can consume k4k events in a pipeline. Mirrors `--log-format=jsonl` for consistency.
- **Final line on success/failure:** always printed, even when the in-place line was active — single line, no in-place tricks. Format: `done` (success) or `k4k: <error>` (failure, mirrors stderr error line).
- **`--no-color`:** disables ANSI in the in-place line; otherwise unchanged.

---

## § User-added

(Add your own questions or override defaults in this section.)
