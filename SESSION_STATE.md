# SESSION_STATE — 2026-06-20 (autonomous build)

## end-to-end CERTIFY back-end (ralph loop)  ← v1 DONE-BAR ACHIEVED, audited GREEN

**ACHIEVED:** `k4kspec certify <file.k4kspec>` produces a coqc-checked, extracted, runnable
**certified** binary + TCB manifest. **ALL SIX example specs certify green** across the whole
v1 fragment — no-file (`upper`, `greet`), single-file (`grepf`, `kvget`, `cutf`), and variadic
(`catf`). FOUR independent fresh-agent audits returned GREEN, each with tamper tests proving the
proof is non-vacuous (corrupting `run` makes coqc reject it). Try:
`dune exec k4kspec/bin/main.exe -- certify k4kspec/examples/grepf.k4kspec` then
`/tmp/k4k_certify/grepf an <some-file>`. Plan + audit criteria + done-bar: `k4kspec/backend/PLAN.md`.
**Feasibility PROVEN** by a hand-written PoC (`k4kspec/backend/poc/`): coqc checks the proof
(no Admitted/Axiom), extraction works, the `upper` binary runs (`upper hello -> HELLO`, exit 0).
Rocq 9.1.1 + Z3 are installed. Ralph-loop protocol: each iteration do the next milestone,
commit, then a FRESH agent audits (criteria in PLAN.md §Audit); fix until a fresh-agent audit is
GREEN, then emit the completion promise. **Loop state below is updated each iteration:**

### Certify-pipeline progress log (newest first)
- 2026-06-20: **M4 COMPLETE — ALL SIX example specs certify GREEN, fresh-agent audited.** Added
  `kvget`+`cutf` (Rocq `split`/`get`/`first`/`any`/`int_of`/`is_decimal`) and `catf` (VARIADIC:
  `Input.contents:list(option bytes)`, `fold_left`/`existsb` over the pre-read contents). Two more
  independent audits (kvget+cutf, then catf+full-regression) returned GREEN with tamper tests
  proving non-vacuity. Commits c7d7536, de9ebb8. Whole fragment certified: no-file (upper,greet),
  single-file (grepf,kvget,cutf), variadic (catf). **Variadic caveat (documented):** the
  file_at-over-argv rewrite assumes the argv element is used ONLY via file_at (the canonical
  variadic pattern). **Remaining big items:** the agent-driven (stochastic) PROOF backend for
  hard proofs where `run` differs from the spec (the central bet); verified extraction / TCB
  shrinking (panel actions); fold the certify pipeline into the KB/PRD as realized-v1.
- 2026-06-20: **M3 DONE — `certify grepf.k4kspec` GREEN, fresh-agent audit GREEN. DONE-BAR MET.**
  Automated `certify` now produces a coqc-checked, extracted, runnable CERTIFIED binary for BOTH
  the no-file fragment (`upper`) AND the file-handling fragment (`grepf`). Independent auditor
  confirmed: 3-way tamper test on grepf's `run` → coqc rejects each (non-vacuous); the binary
  matches the spec on real files incl. trailing-newline / empty-line edge cases; 0 mismatches
  over 39 inputs; manifest honest; 3 distinct generated `.v`. **END-TO-END v1 RUN ACHIEVED;
  promise V1_E2E_GREEN emitted.** rocq_emit.ml now does the file algebra (lines/contains/unlines
  + lambdas + a type env); certify.ml has the file shim + file-materialising cross-check.
  Remaining (future, M4+): variadic + `get`/`split`/`int_of`/`fold`/`first`/`any` for
  kvget/cutf/catf; and the agent-driven (stochastic) backend for HARD proofs where `run` must
  differ from the spec (v1 generates `run` to match the spec, so proofs are easy — honest limit).
- 2026-06-20: **M1+M2 DONE — fresh-agent audit GREEN.** `k4kspec certify <file.k4kspec>` now
  automates emit -> coqc -> extract -> compile(+shim) -> run -> cross-check(oracle) -> manifest
  for the **NO-FILE** fragment. `certify upper.k4kspec` and `certify greet.k4kspec` both green
  (coqc proof CHECKED, no Admitted/Axiom; binary matches the spec on 15 inputs; the two
  generated `.v` DIFFER, so the elaborator is general). An independent auditor confirmed
  **non-vacuity** by tampering `run` 3 ways -> coqc correctly REJECTS each. Files:
  `lib/rocq_emit.ml` (elaborator), `lib/certify.ml` (driver), `bin/main.ml` (`emit`/`certify`),
  `examples/{upper,greet}.k4kspec`. (Fixed: `Abort` added to the certify banned-list.)
  Try: `dune exec k4kspec/bin/main.exe -- certify k4kspec/examples/upper.k4kspec`.

  **NEXT: M3 — the FILE-HANDLING fragment, so `certify grepf.k4kspec` goes green (the done-bar
  for the V1_E2E_GREEN promise; do NOT emit the promise until a fresh agent confirms grepf).**
  Design notes for M3 (in `rocq_emit.ml` + `certify.ml`):
  - Specialise `Input` to the footprint: `FileAt i` adds a field `file1 : option bytes` (the
    file shim reads `argv[i]` -> `Some content` / `None` if absent). Translate `file absent`
    -> `(match file1 i with None => true | _ => false)`; `file.bytes` -> a total accessor
    `(match file1 i with Some c => c | None => EmptyString end)`.
  - Port the blessed algebra to Rocq: `lines`, `split`, `contains`, `unlines`, `filter`/`map`/
    `fold` (combinators take a Rocq `fun`), `get`, `first`, `is_decimal`, `int_of`, `file_at`,
    `opt_bytes`. grepf needs only: `lines`, `filter`+lambda, `contains`, `unlines`, `is_empty`.
    The Rocq defs MUST match `lib/algebra.ml` (esp. `lines` POSIX trailing-newline rule).
  - Lambdas: `rocq_emit.re (Lam(x,body))` -> `(fun x => <body>)`; `Var x` already works.
  - File shim (variant of the no-file one): build `Input` with `file1 = read_opt argv[i]`;
    open ONLY the footprint paths (frame by construction).
  - Proof: the generic case-split tactic already destructs inner `if`s (e.g. grepf's
    `if is_empty matched then 1 else 0`). May need `cbv zeta`/`cbn` to settle `let`s before
    `reflexivity` — adjust the tactic if coqc complains. Test on grepf iteratively.
  - Then M4 (kvget/cutf/catf), M5 (manifest/docs). Audit each milestone with a FRESH agent.
- 2026-06-20: PoC proven (`backend/poc/upper.v` coqc-green + extracted binary runs). Plan
  (`backend/PLAN.md`) written. Ralph loop armed (max-iterations 40, promise V1_E2E_GREEN).

---

## What I built (and why this, not "v1 of k4k")

A **reference-free spec-validation core** for k4kspec — the panel's #1 highest-leverage,
lowest-risk, most-tangible piece, and the one with **no formal-methods dependency** to get
stuck on. It is the *front-end* of v1 (validate a spec against intent), **not** the
certifying back-end (Rocq proof + extraction + certificate), which is weeks of work and
rides the project's central unproven bet — I deliberately did not attempt it.

After your interrupt ("cloning X was only an example"), I recalibrated: the spine is the
**general, reference-free** validation loop where the **human is the oracle of intent**.
Differential testing against a real binary is an *optional clone plug*, clearly labelled.

Everything is in a fresh `k4kspec/` tree, **stdlib-only**, untouched by the (alcotest-broken)
v2 build.

## How to test it (start here)

```sh
cd /mnt/archive/yann/new-home/perso/dev/k4k

# unit tests (stdlib-only, no alcotest):
dune build @k4kspec/test/runtest        # prints "ALL OK"

# the validation harness on the NON-clone spec (no reference tool involved):
dune exec k4kspec/bin/main.exe -- check kvget

# the others:
dune exec k4kspec/bin/main.exe -- check grepf
dune exec k4kspec/bin/main.exe -- check cutf
dune exec k4kspec/bin/main.exe -- check catf

# validate a .k4kspec FILE (write your own — examples in k4kspec/examples/):
dune exec k4kspec/bin/main.exe -- check k4kspec/examples/kvget.k4kspec

# execute a spec as its own model:
printf 'apple\nbanana\ncherry\n' > /tmp/fruit.txt
dune exec k4kspec/bin/main.exe -- run grepf -- an /tmp/fruit.txt   # -> banana

# OPTIONAL clone plug (special case): diff a spec vs a real tool
dune exec k4kspec/bin/main.exe -- check grepf --ref 'grep -F'
```

`check <name>` reports: **examples** (the author's stated intent), **stability**
(exhaustiveness, dead-case heuristic, anti-vacuity), **under-specified dimensions**
(free channels, for explicit sign-off), and an **adversarial sweep** (the spec's behavior
on boundary inputs — *review these: is this what you meant?*). Exit 0 iff it validates.

## What the run already surfaced (the harness earning its keep)

- **`cutf` flagged case #4 (absent-file) as possibly-dead** — neither the examples nor the
  sweep exercised "valid args + absent file". I added the missing example; flag cleared.
  (This is the coverage-gap surfacing working.)
- **clone diff `grepf` vs `grep -F`** found a real semantic divergence: my `grepf` requires
  2 args (exit 2 on one), while `grep -F NEEDLE` reads **stdin** (exit 1). Legitimate design
  difference — exactly what differential testing is for, *when* you're cloning.
- **`grep` on this machine is ugrep 7.5**, not GNU grep (`cut`/`cat` are GNU coreutils 9.10).
  A live instance of the "*which* tool are you cloning?" clarification.

## What is intentionally NOT here

- No Rocq / proof / extraction / certified binary (the back-end; out of scope for 2h).
- `run`'s stdin is empty (none of the 4 specs read stdin); wire real stdin when a spec needs it.
- The blessed algebra has no int->bytes rendering or take/drop/slice yet (grow by need).

## Decisions I made autonomously (all reversible; recorded here + in memory)

- Bytes = OCaml `string` (8-bit clean). Algebra is total + byte-first (`k4kspec/lib/algebra.ml`).
- `lines` = documented POSIX (final `\n` is a terminator, not an empty trailing line);
  `split` is mechanical (keeps every piece). Tested in `test_k4kspec.ml`.
- kvget value = field after the FIRST `=` only (so `k=a=b` → `a`); a defined choice for the demo.
- The adversarial generator is a deterministic heuristic (no randomness); dead-case detection
  is explicitly labelled "heuristic, over sweep" — it can false-positive (as cutf #4 showed).

## Module map (`k4kspec/`)

| file | role |
|---|---|
| `lib/algebra.ml` | the blessed value algebra (total, byte-first) — the audited-once TCB core |
| `lib/ast.ml`     | spec AST (Input/Output, cases/lets/outs, footprint, examples) |
| `lib/eval.ml`    | the spec **oracle**: run a spec → determined (stdout, exit) + stderr constraint |
| `lib/specs.ml`   | grepf / cutf / catf / **kvget** (non-clone) as AST values, with examples |
| `lib/check.ml`   | the reference-free harness (examples / stability / under-spec / sweep). The sweep includes **mutations of your own examples** (drop/add an arg, empty a file, toggle trailing newline, remove a file) — the most relevant boundaries — plus a generic boundary grid |
| `lib/parse.ml`   | surface `.k4kspec` text -> AST (lexer + recursive-descent parser; located `line:col` errors). Round-trip tested against the AST specs |
| `lib/refdiff.ml` | OPTIONAL clone differential vs a reference binary (special case) |
| `bin/main.ml`    | CLI: `list` / `check` / `run` |
| `test/test_k4kspec.ml` | stdlib-only tests (algebra + oracle + all examples + exhaustiveness) |

## Next steps (in leverage order)

1. ~~Surface parser~~ **DONE** (`lib/parse.ml`; `line:col` errors; round-trip tested). `check`/`run`
   take a `.k4kspec` file or a built-in name.
2. **Pin the blessed-def semantics** precisely (Rocq defs + English contract) — they are the
   certified vocabulary (ADR-016 / spec/k4kspec.md §8).
3. Grow the algebra as real specs demand it (int->bytes rendering, take/drop/slice, …).
4. Smarter property generation (shrinking, guard-aware boundary mining) for the sweep.
5. Then the certifying back-end (elaborate → Rocq `spec_rel` + theorem + shim + extraction).

KB for the design behind all this: `kb/INDEX.md` → ADR-014/015/016/017, `kb/spec/k4kspec.md`,
`kb/reports/expert-panel-2026-06-19.md`.
