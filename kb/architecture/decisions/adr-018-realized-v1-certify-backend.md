---
id: adr-018
type: decision
summary: Records the REALIZED v1 certifying back-end. `k4kspec certify <file>` elaborates a spec to Rocq, coqc CHECKS the proof, extracts to OCaml, compiles with an I/O shim, runs, cross-checks vs the oracle, and writes a TCB manifest. All six v1-fragment example specs certify, each independently fresh-agent audited (with tamper tests). Realizes ADR-015 + ADR-016.
domain: architecture
last-updated: 2026-06-20
depends-on: [adr-015, adr-016, glossary]
refines: [adr-016]
related: [adr-008, adr-009]
---

# ADR-018: Realized v1 certifying back-end (Rocq + extraction)

## Status
Accepted / **realized** (2026-06-20). Realizes the design of ADR-015 (k4kspec elaboration) and
ADR-016 (v1 verification model: pinned Rocq + extraction). Built in the `k4kspec/` tree
(`backend/`, `lib/rocq_emit.ml`, `lib/certify.ml`), commits `0f9eb9d..63ee151`.

## What was built

`k4kspec certify <file.k4kspec>` runs the full pipeline:

```
parse -> lib/rocq_emit.ml elaborates to a Rocq .v -> coqc CHECKS the proof -> extract to OCaml
      -> compile (extracted core + I/O shim) -> run -> cross-check vs the Eval oracle -> TCB manifest
```

- **Elaborator (`lib/rocq_emit.ml`).** `Ast.spec -> .v`: a footprint-specialised `Input` record
  (`NoFiles` / `FileAt i` adds `file1 : option bytes` / `FileAtEach` adds `contents : list (option
  bytes)`), `spec_rel : Input -> Output -> Prop` (the relation `R`, from the cases/laws), a
  generated `run : Input -> Output` (a parallel if-chain sharing `spec_rel`'s guards and
  determined-channel expressions, with a concrete choice for each free channel), a GENERIC
  case-split proof, and the extraction directives. A type env tracks let/lambda variable types.
- **Blessed algebra (`backend/Kalgebra.v`).** The certified vocabulary, **audited once** (ADR-016
  §"blessed algebra"). Generated specs `Require Import Kalgebra` rather than re-emitting it, so a
  generated `.v` carries only `Input`/`spec_rel`/`run`/proof. Must match `lib/algebra.ml`.
- **Driver (`lib/certify.ml`).** Emits the `.v`, gates on no `Admitted/Axiom/admit/Parameter/
  Conjecture/Abort`, compiles `Kalgebra.v` then the spec with `coqc`, compiles the extracted core
  with a footprint-aware **I/O shim** (reads exactly the declared footprint paths — frame by
  construction), runs the binary on the examples + the boundary sweep, **cross-checks every result
  against the `Eval` oracle**, and writes a per-certificate TCB manifest.

**The generic-proof insight (why this is automatable for v1):** because `run` is generated to
share `spec_rel`'s guard structure and determined-channel expressions, every proof leaf is
`reflexivity` (determined channels are literally equal) or `discriminate` (a concrete nonempty
message `<> ""`). The tactic is uniform: `intros i; unfold ...; [destruct the footprint option;]
repeat (destruct each if-guard); cbn; repeat split; (reflexivity || discriminate || exact I)`.

## Certified specs (each independently fresh-agent audited)

| spec | footprint | exercises |
|---|---|---|
| `upper`, `greet` | none | argv→stdout, `ascii_upper`, literal concat |
| `grepf` | one file | `filter`+lambda, `lines`, `contains`, `unlines`, the inner `if` |
| `kvget` | one file | `split`, `get`, `first`, `any`, `==`, nested lets |
| `cutf` | one file | `int_of`/`is_decimal` (nat parsing), `map`, field cut |
| `catf` | variadic | `fold_left`/`existsb` over the pre-read `contents`, frame |

**Four** independent fresh-agent audits returned GREEN. Each ran `coqc` itself and — the decisive
check — a **tamper test**: corrupt the extracted `run` (wrong stdout / wrong exit) and confirm
`coqc` then REJECTS it. It did, every time, proving `spec_rel` is **non-vacuous**. Binaries
cross-checked against an independent oracle on 15–52 inputs each, 0 mismatches, including
trailing-newline / empty-line / duplicate-file / missing-file edge cases.

## The concrete TCB (what a v1 certificate trusts)

A Tier-A certificate asserts: *the extracted implementation is proven (coqc) to satisfy `spec_rel`,
the relation denoted by the signed k4kspec, MODULO:*

1. the **Rocq kernel** + **extraction** (Coq→OCaml; an unverified trusted step, ADR-016 §2);
2. the **OCaml compiler** (`ocamlfind ocamlopt`) + runtime;
3. the **blessed value algebra** `backend/Kalgebra.v` (audited once — the spec's *meaning*);
4. the **I/O shim** (per class × prover; real argv/stdin/fs ↔ `Input`/`Output`, frame-enforcing);
5. the **elaborator** `lib/rocq_emit.ml` (per-spec, mechanical; emits `spec_rel`/`run`/proof).

The manifest names these per certificate. Honest scope: this is "proven modulo the named TCB", not
unconditional certainty (Klein/Ringer, panel).

## Honest limitation (stated in every manifest)

**v1 generates `run` to match the spec**, so the proof is easy. This proves the *pipeline* end to
end and that the *certificate is real* (kernel-checked, tamper-verified non-vacuous) — but it is
**not** hard proof automation, and it collapses the two-artifact separation (the elaborator writes
both `spec_rel` and `run`). Replacing the deterministic `run`-generator with a **stochastic agent
proof backend** — where `run` is developed *differently* from the spec and the proof is genuinely
hard, with coqc as the only gate — is the project's central remaining bet (forthcoming ADR-019).
One variadic caveat: the `file_at`-over-argv rewrite assumes the argv element is used only via
`file_at` (the canonical variadic pattern).

## TCB-shrinking roadmap (ADR-016 actions, status)

- **Blessed algebra audited-once (`Kalgebra.v`)** — DONE (commit `63ee151`).
- **Statement-preserving elaborator** (ADR-016 §5) — NEXT: property-test (then prove) that the
  emitted `spec_rel` denotes the same `R` as the surface, against a reference denotational semantics.
- **Verified extraction** (Leroy/Klein, panel) — adopt CertiCoq / a CakeML-style path, or keep
  counting extraction explicitly in the manifest (current).
- **Shim verification / translation validation** — give the shim its own signed observational spec.

## What this means for implementers

- The certificate is only as strong as the **TCB manifest** is honest; never describe a Tier-A
  artifact as "certified" without the qualifying clause.
- The cross-check (binary vs `Eval` oracle) is a *belt-and-braces* validation on top of the proof,
  not the proof itself; the proof is the coqc check of `correct : forall i, spec_rel i (run i)`.
- The next phase (ADR-019) swaps the `run`-generator for an agent backend (ADR-009 wire protocol),
  keeping coqc as the accept/reject gate — the harness's propose/accept-or-reject pattern at the
  proof level.
