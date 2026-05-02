---
id: conventions.code-style
type: concept
summary: OCaml code-style rules for k4k — file/function size caps, naming, module structure, doc-comment conventions, mandatory `@invariant` annotations.
domain: conventions
last-updated: 2026-05-02
depends-on: [glossary, architecture.overview, properties.functional]
refines: []
related: [conventions.error-handling, conventions.testing-strategy]
---

# Code Style

## Hard limits

| Rule                                                     | Limit         | Enforcement              |
|----------------------------------------------------------|---------------|--------------------------|
| File length                                              | ≤ 200 lines  | CI lint                  |
| Function length                                          | ≤ 30 lines   | CI lint                  |
| Module per file                                          | exactly one  | naming convention + lint |
| `.mli` for every public `.ml`                            | required     | CI lint                  |
| Comment ratio (over-target; never pad)                   | ≥ 30%        | informational warning    |
| Cyclomatic complexity                                    | ≤ 10         | CI lint                  |

A file or function that exceeds the limit is split, never raised.

## Naming

- Modules: `Snake_case` (one word per file: `Gap_step`, `Verifier_external`).
- Functions: `snake_case`. Predicates end with `?` only inside doc-comments; OCaml lacks the syntax — use `is_<x>` or `has_<x>`.
- Type aliases: `snake_case`. Variant constructors: `Capitalized`. Polymorphic variants only at module boundaries (e.g. `Agent_backend.invoke` return type).
- Test names: `P<id>_<slug>` for property-bound tests; `T<id>_<slug>` for edge-case tests; `NF<id>_<slug>` for non-functional measurements.

## Module structure

Every public `.ml` has a paired `.mli` whose top is:

```ocaml
(** [<module name>] — <one-line purpose>.

    This module is responsible for <what it does and why>. It implements
    <which spec features / properties: P1, P5, ...>.

    Key design decisions: <DI flag, error-handling approach, ...>.
*)
```

## Doc-comments on public functions

Every signature in an `.mli` carries:
- A one-sentence purpose line.
- `@param` for each parameter, with semantic meaning (not "the int").
- `@return` if non-trivial.
- `@raise` listing every exception (use `Error.K4k_error of error`'s constructors by name).
- `@invariant` referencing the property (`P3`, `P14`, `NF1`, …) this function helps enforce.
- `@example` for non-trivial functions.

Example:
```ocaml
(** [canonicalize ast] returns a byte-deterministic canonical form of [ast].

    @param ast The raw [Characterization.t] possibly produced from a stochastic agent run.
    @return A [Characterization.t] whose [hash] field is set; structurally
            equivalent ASTs hash equal.
    @invariant P4 — the determinism contract holds on canonical ASTs.
    @raise Error.K4k_error E_format on schema violations. *)
val canonicalize : Characterization.t -> Characterization.t
```

## Inline comments

Defaults: write none. Add a comment only when the **why** is non-obvious — a hidden constraint, a workaround, an algorithmic step that requires justification. Never explain *what* the code does — names should already do that.

Two specific places where comments are required:
- **Conditionals on policy boundaries** (`if status = Established then ...`) — comment cites the property ID gating the branch.
- **Magic constants** (`5_000_000` for the file-size cap) — comment references the spec line.

## Imports

- `open!` only at the top of `.ml`; never inside functions.
- `open!` is preferred over `open` so unused-open warnings remain on.
- Allowed always-open modules: `Stdlib`. Project conventions are in module `K4k_prelude`; explicit `open! K4k_prelude` is required per file when used.

## Types over strings

Anywhere a string carries semantic structure (a property ID, a section ID, a path), wrap it in a private type:

```ocaml
module Property_id : sig
  type t
  val of_string : string -> (t, [> `Invalid ]) result
  val to_string : t -> string
end
```

No `type property_id = string` aliases at signature boundaries.

## Forbidden patterns

- `Obj.magic`, `Obj.repr` — never.
- `Marshal.*` — never (canonicalization must be byte-deterministic; `Marshal` is not).
- `Sys.command` — use `Unix.execvp` or higher-level wrappers in `lib/Subprocess`.
- `Stdlib.print_*` for user-facing output — go through `Logger`.
- `Stdlib.read_line` and friends — k4k is non-interactive; user input goes through `<file.k4k>`.
- `try ... with _ ->` (catch-all) — match specific exceptions or rethrow. The audit will flag.

## Source-tree organization

Per `architecture/overview.md`. Code that does not fit any module either becomes a new module (with its own KB linkage) or is a sign of a misdrawn seam — fix the architecture first.

## Agent notes

> **The 30-line function rule is real.** It exists because every `Gap_step` patch passes through human review, and 30-line diffs review faster than 100-line diffs. Don't smuggle longer functions in via `let foo x = let g y = ... in g (h (i (j x)))` chains.

## Related files

- `error-handling.md` — error hierarchy + raising rules
- `testing-strategy.md` — naming and structure of tests
- `architecture/overview.md` — the source tree these rules govern
