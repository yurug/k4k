# PLAN — end-to-end v1 CERTIFY pipeline (the back-end)

## Goal
An automated command `k4kspec certify <file.k4kspec>` that turns an in-fragment spec into a
**machine-checked, extracted, runnable CERTIFIED binary** + a TCB manifest:

    parse -> elaborate to Rocq (.v) -> coqc (checks the proof) -> extract to OCaml
          -> compile (extracted core + I/O shim) -> run -> cross-check vs the oracle -> manifest

## Proven feasible (do not re-litigate)
`backend/poc/upper.v` + `backend/poc/main_upper.ml`: a HAND-WRITTEN Rocq development for the
`upper` spec that coqc checks (no Admitted/Axiom), extracts (`bytes = char list`,
`input = bytes list`, `output = {stdout;stderr;exit}`), compiles with a shim, and runs
(`upper hello -> HELLO`, exit 0; bad arity -> exit 2). The job is to **GENERATE** such a .v
from the parsed AST, for the whole fragment — not to hand-write per spec.

## Architecture (to build)
- `backend/Kalgebra.v` — the blessed value algebra IN Rocq (audited once): the certified
  vocabulary. Start: `up`/`up_ascii`, `len`, `append`, `one_nonempty_line`. Grow per fragment
  (file specs need `lines`,`split`,`contains`,`filter`,`map`,`fold`,`get`,`first`,`int_of`,
  `is_decimal`,`file_at`/option, ...). MUST match `lib/algebra.ml` semantics (that's the TCB
  link: the spec means whatever these defs say).
- `lib/rocq_emit.ml` — AST -> Rocq .v source: footprint-specialised `Input`/`Output`,
  `spec_rel` (from cases/laws), `run` (a parallel if-chain matching spec_rel's guards, with a
  concrete choice for each free channel), the correctness theorem + a GENERIC proof, and the
  extraction directives.
- `lib/certify.ml` (+ a `certify` subcommand in `bin/main.ml`) — the driver: emit .v -> run
  `coqc` -> extract -> compile extracted+shim -> run the binary on the spec's examples + a
  boundary sweep -> cross-check each result against `Eval.run` (the oracle) -> write a TCB
  manifest. Returns pass/fail with diagnostics.
- shim templates per class: a no-file shim (like `poc/main_upper.ml`) and a file shim that
  resolves the footprint and reads exactly those paths (frame by construction).

## The key automation insight (why the proof is generatable)
`run` is generated to SHARE `spec_rel`'s guard structure and its determined-channel
expressions, and to emit a concrete nonempty message on each free channel. So every proof leaf
is `reflexivity` (determined channels are literally equal) or `discriminate`
(`<concrete message> <> ""`). The emitted proof is uniform:

    Proof. intros i. unfold spec_rel, run, one_nonempty_line.
      <case-split on each guard boolean / argv shape>; cbn; repeat split;
      (reflexivity || discriminate). Qed.

Honest limitation (document in the manifest): for v1 the implementation is generated to match
the spec, so proofs are easy; swapping the deterministic generator for a stochastic agent
backend (for impls that differ from the spec and need hard proofs) is the NEXT phase.

## Milestones (each one GREEN-audited before moving on)
- **M1** — automate `upper` (no-file) end-to-end via `certify` (generate the .v, coqc, extract,
  compile, run, cross-check, manifest). The generated .v must match the PoC's guarantees.
- **M2** — generalise the no-file fragment (arbitrary guards + `ascii_lower`/`len`/`concat`/
  comparisons); certify a 2nd no-file spec to prove the elaborator is GENERAL, not hardcoded.
- **M3** — file-handling fragment: model the footprint + `option` in Rocq, port the blessed
  algebra (`lines`/`split`/`contains`/`filter`/`get`/`first`/`int_of`/`is_decimal`/`fold`/
  `file_at`/`opt_bytes`) + the file shim; certify `grepf`, then `kvget`.
- **M4** — `cutf`, `catf`.
- **M5** — TCB manifest polish, `certify` docs, a self-check.

## Audit criteria (the FRESH agent must verify, adversarially)
1. `certify <spec>` runs from a CLEAN tree and produces a binary (no pre-built artifacts).
2. The generated `.v` contains NO `Admitted`/`Axiom`/`admit`/`Parameter`/`Conjecture`; `coqc`
   exits 0.
3. The theorem is `forall i, spec_rel i (run i)` with the REAL `spec_rel` derived from the
   surface (spot-check it against the spec's cases); `run` is a separate definition.
4. Non-vacuity: `spec_rel` actually constrains — e.g. tampering `run`'s output makes `coqc`
   FAIL (the audit should try this), and/or `spec_rel i o` is False for some wrong `o`.
5. The binary matches `Eval.run` (the oracle) on the examples + a boundary/random sweep.
6. Generality: certifying a DIFFERENT spec yields a different, still-checking `.v` (≥2 distinct
   specs certified). Not a hardcoded `upper.v`.
7. The TCB manifest honestly lists every trusted component (Rocq kernel, extraction, ocaml
   compiler, `Kalgebra.v`, the shim, the elaborator).
8. No hand-editing of generated artifacts between generation and checking.
Audit returns **GREEN** only if all hold; otherwise it lists concrete, actionable issues.

## Done bar / completion promise
When a FRESH-agent audit returns FULLY GREEN for the automated `certify` on **`upper`
(no-file) AND `grepf` (file-handling)**, output `<promise>V1_E2E_GREEN</promise>`.
Fallback (only if the file fragment can't be finished within max-iterations): a clearly-labelled
partial green on the no-file fragment with ≥2 distinct specs certified.

## Iteration protocol (each ralph iteration)
1. Read this PLAN, `SESSION_STATE.md`, and recent `git log`.
2. Do the next milestone/fix. Build. Commit (small, descriptive).
3. Spawn a FRESH general-purpose agent to audit against the criteria above (it runs `certify`
   itself; it does NOT trust prior claims).
4. Record the verdict + concrete issues in `SESSION_STATE.md`; fix them next iteration.
5. Honesty: never fake/Admit a proof; never hand-edit generated `.v` to pass; never claim green
   without a fresh agent confirming. Keep `SESSION_STATE.md` the durable source of truth
   (context may be summarised between iterations).
