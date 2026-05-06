---
id: conventions.error-handling
type: concept
summary: How errors are raised, mapped to exit codes, scrubbed of secrets, and presented to the user. Closed-set discipline — every emit site has a registered ID.
domain: conventions
last-updated: 2026-05-02
depends-on: [glossary, spec.error-taxonomy, properties.functional, properties.non-functional]
refines: []
related: [conventions.code-style]
---

# Error Handling

## Closed-set discipline

Every user-visible error matches an entry in `spec/error-taxonomy.md`. Adding a new error class is a KB-first change: extend the taxonomy, then add a constructor to `Error.t`, then update the emit site. Reverse order is a methodology bug (`P7`).

## OCaml hierarchy

Defined in `lib/Error`:

```ocaml
type error =
  | E_format               of { line : int; col : int; reason : string }
  | E_unstable             of issue list
  | E_version              of { found : int; supported : int list }
  | E_class_unsupported    of string
  | E_budget               of { used : int; cap : int }
  | E_max_steps            of int
  | E_agent_unavailable    of string
  | E_verifier_unavailable of string
  | E_verifier_tool_error  of string
  | E_disk_full            of string
  | E_state_corrupt        of string
  | E_encoding             of int                 (* byte offset *)
  | E_file_not_found       of string
  | E_file_too_large       of int

exception K4k_error of error
exception Invariant_violation of string
```

Mapping to exit codes lives in `Error.exit_code_of : error -> int` (table per `spec/error-taxonomy.md`). User-visible message generation lives in `Error.render : error -> string`.

## Raising

- **`raise (K4k_error E_x)`** — every user-facing failure. The constructor encodes the *what*; the wrapping `try ... with K4k_error e -> Logger.error e; exit (exit_code_of e)` lives in `bin/main.ml`.
- **`raise (Invariant_violation msg)`** — for code-internal contradictions (e.g. `lib/cotype.ml` being bypassed and the interaction file being written through any other path). Exit 64+. These are bugs; the user should report them.
- **No naked `failwith`** anywhere. Use a typed constructor.

## Catching

- `try ... with K4k_error e -> ...` only at the top level (`bin/main.ml`) and at *retry boundaries* (e.g. `Backend_external` retries on transient backend-tool failures).
- No catch-all (`with _ ->`). Match the specific constructor.
- A function that catches `K4k_error` must either re-raise after logging, or convert to a domain-specific value (e.g. `Stub_agent` translates network failures into a deterministic `Tool_error`).

## Logging an error

Two channels per emission:
1. **Human-readable on stderr**: `Logger.error_user e` writes one line, `k4k: <message>` prefix.
2. **Structured in JSONL**: `Logger.error_jsonl e` appends `{"ts":..., "level":"error", "code":"<id>", "details":...}` to `.k4k/log.jsonl`.

Both happen automatically when the top-level handler runs `Logger.error e`. Never bypass.

## Secrets scrubbing (NF5)

`Logger.scrub` runs over every string before it is written to stderr or JSONL. Pattern:

```
(?i)(api[_-]?key|token|secret|password|bearer)\s*[:=]\s*\S+
```

Matches are replaced with `<scrubbed>`. The function is regression-tested with a poison-canary value (see `NF5` measurement procedure).

Additionally:
- The full process environment is *never* logged, even at `-vv`. If you need to debug an env issue, log only the variable names you read, never the values.
- Subprocess invocations use `Unix.execvp` directly; no string interpolation that could leak via `Sys.command`.

## Recovery hints

Every `error` constructor has a fixed recovery hint (per `spec/error-taxonomy.md`). They are part of the user contract — keep them stable across releases.

## Internal panics (exit 64+)

`Invariant_violation` is reserved for cases where continuing would corrupt user state. Examples:
- `EOWNERSHIP_VIOLATION` (P1).
- Inconsistent manifest state (e.g. `desired/spec.json` references a property absent from `gap/properties.json`).

Panics dump a truncated stack trace to `.k4k/log.jsonl` (max 8 KB per entry) so post-mortem is possible without running again.

## Retries

Three places allow retries; nowhere else does:
- **`Backend_external.invoke`**: up to 3× on transient backend-tool failures (exit code 1, exponential backoff). All retries count against budget.
- **`Verifier_external.run`**: zero retries. A `Tool_error` here (verifier exit ≥ 1, missing/unparseable result file, timeout) is a real error.
- **`Persist.atomic_write`**: zero retries on `ENOSPC`; rollback and surface `EDISK_FULL`.

A retry that succeeds is logged at `level: "warn"` (so audit can see how flaky a run was).

## Agent notes

> **Don't add new error variants opportunistically.** A new variant means a new line in `spec/error-taxonomy.md`, a new exit code potentially, a new docstring everywhere it might be raised. If you find yourself reaching for `failwith`, stop and decide: is this an existing error class? A new one? Or an invariant violation?

## Related files

- `spec/error-taxonomy.md` — the closed catalog
- `properties/functional.md#P7` — the invariant this convention enforces
- `properties/non-functional.md#NF5` — secrets-quarantine measurement
