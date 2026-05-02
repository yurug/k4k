---
id: adr-001
type: decision
summary: k4k v0 is implemented in OCaml ≥5.1, built with dune + opam. Rationale and consequences.
domain: architecture
last-updated: 2026-05-02
depends-on: [domain.prd]
refines: []
related: [adr-004, conventions.code-style]
---

# ADR-001: OCaml + dune

## Status
Accepted (2026-05-02).

## Context
k4k v0 must be built in *some* language. The relevant constraints:
- v0 only writes OCaml programs (verifier is `dune-ocaml`); having k4k itself in the same language reduces the test/dogfood gap.
- The verifier ecosystem cited in `kb/NOTES.md` (Rocq, Frama-C) is OCaml-native.
- The user's affiliation (Nomadic Labs) is OCaml-heavy; familiarity is high.
- Strong static typing helps enforce the harness's invariants at compile time (e.g. closed-set error variants, signature conformance for backends/verifiers).
- Alternatives considered: Rust (great tooling, heavier ramp-up, no payoff over OCaml here); Python (faster prototype, weaker invariants, signature-less plugins); Go (fine, but no ecosystem fit).

## Decision
Implement k4k in OCaml ≥ 5.1 with dune + opam. Lockfile via `opam.lock`. No effects/domains required for v0; the version floor is set at 5.1 in case future concurrent agent calls benefit.

## Consequences
- All v0 contributors must have an OCaml toolchain.
- Source trees follow OCaml conventions (`bin/`, `lib/`, `test/`, `.opam`, `dune-project`).
- The verifier interface is a first-class module signature — a natural fit for OCaml's module system.
- Trade-off accepted: smaller community than Rust/Python, slower onboarding for non-OCaml engineers.

## What this means for implementers
- One module per file, `.ml` + `.mli`. No anonymous let-bindings exposed.
- No `Stdlib.Obj`, no `Marshal`, no `Sys.command` (use `Unix` for fine-grained control). Canonicalization is byte-deterministic; `Marshal` is not.
- Lint and typecheck via `dune build @check` are enforced in CI.
