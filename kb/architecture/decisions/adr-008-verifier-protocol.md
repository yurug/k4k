---
id: adr-008
type: decision
summary: k4k carries zero verifier-specific code. Verifiers are external executables conforming to a documented wire protocol; k4k ships one generic adapter (Verifier_external) and a stub.
domain: architecture
last-updated: 2026-05-02
depends-on: [adr-004, glossary, spec.api-contracts]
refines: [adr-004]
related: [external.verifier-protocol]
---

# ADR-008: Wire-protocol verifier; k4k ships no verifier-specific code

## Status
Accepted (2026-05-02). Supersedes the v0-only narrowing in ADR-004 ("v0 ships dune-ocaml only"); the *pluggability* rationale of ADR-004 stands.

## Context

ADR-004 set up a pluggable verifier interface as an OCaml module signature, then narrowed v0 to ship a single concrete adapter (`Verifier_dune_ocaml`) baked into `lib/`. The v0 implementation accumulated dune-specific knowledge inside k4k:

- `lib/verifier_dune_ocaml.ml` — invocation, exit-code interpretation
- `lib/dune_output.ml` — alcotest stdout/stderr regex parsing
- `kb/external/dune.md` — runtime-behavior documentation framed as a *k4k* concern

When `Verifier_rocq` was proposed, the natural-by-precedent move was to add `lib/verifier_rocq.ml` + `lib/rocq_output.ml` + `kb/external/rocq.md`. This would have doubled the verifier-specific surface inside k4k for every new verifier we add.

`kb/NOTES.md`'s thesis is that POSIX-like programs have "behavior exclusively made of well-specified I/Os". A coding agent that builds those programs cannot itself violate that thesis by carrying tool-specific output regexes. The leak in v0 was tolerable as expedience; expanding it would be an architectural error.

## Decision

1. **k4k ships only one verifier adapter: `lib/Verifier_external`** — a generic process-spawner that invokes a configured executable per the protocol in `kb/external/verifier-protocol.md` and parses a JSON result. Plus `lib/Verifier_stub` for tests.
2. **`lib/Verifier_dune_ocaml` and `lib/Dune_output` are removed.** Their behavior — invoking `dune build @runtest`, parsing alcotest output — moves to a standalone executable shipped at `examples/verifiers/dune-ocaml/`. That executable is a worked example, not a privileged piece of k4k.
3. **The verifier is configured in the interaction file's frontmatter** (`k4k.verifier.command`, `k4k.verifier.timeout_s`). No default `command` — declaring it is part of stability per `EUNSTABLE`.
4. **The OCaml-internal `Verifier.S` signature is retained** for type-level wiring inside k4k, but no longer treated as the public extension surface — that role moves to the wire protocol.
5. **Adding a new verifier (Rocq, Frama-C, Verus, AFL, anything) requires zero changes to k4k's source.** It is a new external executable conforming to the protocol, plus documentation co-located with that executable.

## Consequences

**Wins:**
- k4k's `lib/` is verifier-agnostic by construction. The "30 modules" inventory loses two and gains one (net −1).
- The KB's `external/` directory loses a tool-specific document (`dune.md`); the protocol doc replaces it. Future verifiers do not bloat the KB.
- The user's interaction file is now self-describing about *which* verifier it expects — a property that audit tooling can leverage.
- Phase-5 audit Axis 5 (spec compliance) tightens: every line in `lib/` either implements the harness or implements the protocol; there is no "verifier-specific" middle category.

**Costs:**
- Refactor cost: existing tests that referenced `Verifier_dune_ocaml`/`Dune_output` need to be updated or moved. The `S1_echo_first_run_e2e` integration test now invokes the example binary via the protocol; the assertion content is unchanged.
- The example binary still lives in this repo (`examples/verifiers/dune-ocaml/`). It is built by the same `dune-project` for convenience but is not part of the k4k installable surface. Users who do not need the dune verifier do not link it.
- The frontmatter `verifier:` field becomes a required user-owned section (or required frontmatter key — see `spec/config-and-formats.md` for the exact placement). Existing `.k4k` fixtures need updating.

## What this means for implementers

- **Never reach for `external/<tool>.md` from k4k's source.** If you find yourself wanting to know "how does dune format its output", you are in the wrong file — that knowledge lives in the verifier executable, which has its own README.
- **The `Verifier_external` adapter is the only `lib/verifier_*.ml` that may exist** (alongside `Verifier_stub` for tests).
- **Tests that need a real verifier** invoke `examples/verifiers/dune-ocaml/main.exe` (built by dune as part of the same project) via the protocol. They do not import any module specific to dune.
- **The reference verifier is a worked example, not a default.** k4k does not implicitly fall back to it. The interaction file MUST declare a `command`.
- **For agents writing patches**, the prompt template `prompts/gap-step.md` will need to mention the *protocol* (the test convention `P<id>_<slug>` is a per-verifier choice, not a k4k convention). Updating that prompt is part of this retrofit.

## Migration story for v0 users

Anyone running v0 with the bundled `Verifier_dune_ocaml` must update their `<file.k4k>` frontmatter to declare `k4k.verifier.command` pointing at the example binary. The example binary's path is documented in `examples/verifiers/dune-ocaml/README.md`.

## Relationship to ADR-004

ADR-004 said:
> Verifiers are pluggable via the same module-signature pattern as backends.

ADR-008 keeps the *pluggability claim* and changes the *plug shape* from "OCaml module signature" to "wire protocol over JSON files". The `Verifier.S` signature still exists in `lib/`; it just has only one production-grade implementation (`Verifier_external`) and a test stub.
