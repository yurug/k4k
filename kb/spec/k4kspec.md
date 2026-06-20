---
id: spec.k4kspec
type: spec
summary: The k4kspec language reference (v3, in progress). The concrete observational specification language — semantic domain, the relation R, the surface forms (interface/footprint/cases/laws/examples/errors), the value algebra, the filesystem frame/footprint model, and the under-specification posture. Worked examples included. Open items flagged.
domain: spec
last-updated: 2026-06-20
depends-on: [glossary, adr-015, adr-016, adr-017]
refines: []
related: [domain.prd]
---

# k4kspec — language reference (v3, in progress)

> Status: the **surface, value algebra, and fs model are settled** from the 2026-06-19/20 design. The precise blessed-def semantics, the IR, the I/O shim, and the validation oracle are **not yet pinned** — see *Open* at the end. This is the certification anchor's language (Artifact 1, ADR-015).

## 1. Semantic domain (the `cli` class, v1)

```
Input  = { argv  : list bytes          # positional args; program name EXCLUDED; 0-based
         , stdin : bytes                # finite (read fully); streaming is out-of-fragment
         , env   : name ⇀ bytes         # only DECLARED vars are in scope
         , reads : path ⇀ bytes }       # only the DECLARED, argv-parametric read-footprint
Output = { stdout : bytes
         , stderr : bytes
         , exit   : int[0..255]
         , writes : path ⇀ option bytes }  # Some b = final content, None = deleted; rest framed
```

The program is a total deterministic function `run : Input → Output`.

## 2. The spec denotes a relation `R ⊆ Input × Output`

`R i o` holds iff `o` is an **acceptable** output for input `i`. Correctness theorem: `∀ i. R i (run i)`. A singleton `R` is fully determined; a non-singleton `R` is deliberate **under-specification** (see §6). The denotation is the **conjunction** of the surface forms.

## 3. Surface forms

```
interface cli "NAME":
  reads:  <footprint entries>          # see §5; omit / "nothing" if none
  writes: <footprint entries>
  env:    <declared var names>

errors:                                # optional; named (exit, exact stderr) — SUGAR over cases
  NAME      : exit N, stderr <bytes-expr>
  NAME(p)   : exit N, stderr <bytes-expr using p>

cases on argv, file(s):                # ORDERED, first-match wins
  when <computable bool guard>: <output constraints>   |   raise <error>
  ...
  otherwise: <output constraints>      # makes the table total

laws:                                  # cross-cutting; relational propositions (∀/∃ allowed)
  - <proposition over (input, output)>

examples:                              # concrete rows, checked against the denotation
  <input> -> <output>
```

- **CASES** — a decision table on the input. **Guards must be computable booleans**; ordered first-match (so a later case sees the earlier guards as false, which keeps footprint references well-defined). Exhaustive (via `otherwise`) ⇒ totality.
- **LAWS** — relational properties; may use arbitrary `∀/∃` and law-only predicates (`sorted`, `permutation`, `distinct`). Discharged by proof, never computed; **illegal in guards**.
- **EXAMPLES** — concrete rows, statically checked to satisfy `R`. Reader aids + regression anchors; a contradictory example is a stability error.
- **ERRORS** — optional named-error table; `raise NAME` is pure sugar for setting `(exit, stderr)`. Use it only when pinning the message (critical / machine-facing). Ordinary diagnostics under-specify instead (§6).

## 4. Value algebra

**Principle (the load-bearing one):** the blessed library holds **mechanical, opinion-free, total** primitives. Any behavioral *choice* a spec needs to control lives **in the spec, visible to the reviewer** — never hidden in a library default. A primitive may encode an *opinion* only when it is a single widely-known **standard**, precisely documented in its blessed def, and the mechanical version remains available as an escape hatch.

**Disciplines:** every primitive is **total** (partial ops are default- or option-valued); **byte-first** (`text` is a UTF-8 refinement reached only via `decode : bytes → option text`); the set is **closed** (no inline new primitives; `let` is abbreviation only). Each primitive has one prover-realized def, audited once per prover (TCB).

**Types:** `bool`, `int` (ℤ; refinements `int[0..255]`, `int[≥0]`), `byte`, `bytes`, `list α`, `option α`, `path`, tuples/records, `text`.

**Primitive set (v1; grow by need, each addition audited):**
```
logic   true false not && || => <=>   if c then a else b
int(ℤ)  + - *  = ≠ < ≤ > ≥  min max abs   div(a,b,dflt) mod(a,b,dflt)
seq     len ++ []  at(xs,i):opt get(xs,i,dflt) head(xs,dflt) tail last(xs,dflt)
        take drop slice rev mem(x,xs) index_of(x,xs):opt  first(xs,p,dflt)
bytes   split(b,sep):list  join(xs,sep)  lines(b):list  unlines(xs)        # split mechanical;
        starts_with ends_with contains  replace(b,old,new)                 # lines = documented POSIX
        ascii_upper ascii_lower  byte_at(b,i):opt  decode(b):opt text  encode(t):bytes
parse   int_of(b):int (dflt 0 on non-decimal)   is_decimal(b):bool
files   present(f) absent(f)  f.bytes  file_at(pathbytes):file  resolve(base,p)
combi   map(xs,f) filter(xs,p) count(xs,p) all(xs,p) any(xs,p) find(xs,p):opt fold(xs,init,f)
law     sorted permutation distinct  ∀x:τ.P  ∃x:τ.P                        # NEVER in guards
```

**Lambdas:** allowed **only** as arguments to the blessed combinators, with a body that is a blessed-total expression in the bound variable(s) (no recursion, no nested `∀/∃` in guard position). May capture enclosing `let`-bindings. This keeps higher-order use bounded, total, readable, and trivially elaborable. `fold` is the escape hatch; most specs use `map`/`filter`/`count`.

**`ascii_upper` is the cautionary case:** it folds only `a–z`; bytes ≥ 128 are untouched. An `echo --upper` spec therefore says *ASCII* upper-casing, visibly — not Unicode. That is where the model/reality gap hides, and byte-first forces honesty about it.

## 5. Filesystem: frame + footprint

**The budget rule:** the footprint is a function of `argv` (and declared env), **never of file contents**. A program whose touched-file set depends on what it *reads* needs an unbounded model and is out-of-fragment.

- The header declares a finite **read-set** `RS(i)` and **write-set** `WS(i)` as functions of `argv`. Footprint entries: a fixed path, a single argv-parametric path (`file at argv[1]`), or **variadic-over-argv** (`file at each of argv[*]`, finite per input — `cat`-class).
- `Input.reads : RS(i) ⇀ bytes`; the spec asserts behavior is **determined by** `(argv, stdin, env↾declared, fs↾RS(i))` and nothing else.
- `Output.writes : WS(i) ⇀ option bytes` (`None` = deleted). Every path **outside `WS(i)` is framed** — provably unchanged — the free "touches nothing else" property.
- **Frame is shim-enforced, content is proof-enforced:** the I/O shim opens exactly `RS(i)` and writes exactly `WS(i)`, so the frame holds by construction; the proof establishes the content relation `R`.

**Out-of-fragment (trip the simplicity budget; named as scope/TCB assumptions):** directory traversal/globbing, symlinks (paths pre-resolved by the shim), permission/mode/ownership bits, write *order* and crash atomicity (v1 models only the **final** fs state), concurrent external mutation during the run, special files, content-derived footprints.

## 6. Under-specification posture (ADR-016/017)

For each output channel there are exactly two coherent positions, no fake middle:

1. **It matters → pin it** (exact bytes, or a structural envelope that is an exact function of the input). Certified.
2. **It genuinely doesn't matter → say so explicitly** (`any`, `one nonempty line`, or a loose regex envelope). The certificate makes *no claim* about the content.

The certified part of an error path is already the part that matters: the **case guard certifies detection**, the **exit code certifies the machine signal**; only the *prose* is free. So `one nonempty line` is the right **default for human diagnostics** (and faithful to Unix: stderr wording is not contract; exit codes + stdout are). Concrete preferences for the free part go in the **guidance document** (ADR-017), best-effort and uncertified.

**Safety valve:** at sign-off, k4k **surfaces every under-specified observable dimension** for explicit acknowledgment, so deliberate under-spec (intended) is distinguished from a forgotten constraint (a bug). The certificate scope discloses which channels are agent-authored/uncertified.

## 7. Worked examples (validated on paper, 2026-06-20)

```
interface cli "grepf":                 # grepf NEEDLE FILE
  reads: file at argv[1] ; writes: nothing
cases on argv, file:
  when len(argv) != 2:  exit 2 ; stderr: one nonempty line ; stdout: ""
  when file absent:     exit 2 ; stderr: one nonempty line ; stdout: ""
  otherwise:
    let matched = filter(lines(file.bytes), \L -> contains(L, argv[0]))
    stdout: unlines(matched) ; stderr: "" ; exit: if matched == [] then 1 else 0
```

```
interface cli "cutf":                  # cutf DELIM N FILE
  reads: file at argv[2] ; writes: nothing
cases on argv, file:
  when len(argv) != 3:           exit 2 ; stderr: one nonempty line ; stdout: ""
  when len(argv[0]) != 1:        exit 2 ; stderr: one nonempty line ; stdout: ""
  when not is_decimal(argv[1]):  exit 2 ; stderr: one nonempty line ; stdout: ""
  when int_of(argv[1]) < 1:      exit 2 ; stderr: one nonempty line ; stdout: ""
  when file absent:              exit 2 ; stderr: one nonempty line ; stdout: ""
  otherwise:
    let n = int_of(argv[1])
    stdout: unlines( map(lines(file.bytes), \L -> get(split(L, argv[0]), n - 1, "")) )
    stderr: "" ; exit: 0
```

```
interface cli "catf":                  # catf FILE...
  reads: file at each of argv[*] ; writes: nothing
cases on argv, files:
  when len(argv) == 0:                       exit 2 ; stderr: one nonempty line ; stdout: ""
  when any(argv, \a -> absent(file_at(a))):  exit 2 ; stderr: one nonempty line ; stdout: ""
  otherwise:
    stdout: fold(argv, "", \acc a -> acc ++ (file_at(a)).bytes) ; stderr: "" ; exit: 0
```

**Finding from the exercise:** faithful CLI specs are dominated by **input-validation cases** (the argv→behavior map *is* the program; totality forces every error path explicit). "Simple spec" = a short core transformation + an exhaustive, boring error decision-table — reviewable, but *wide*. The recurring argv-parsing boilerplate is the pressure that will later justify a blessed **argv-grammar sugar** (declare positionals/flags/types → desugars to guard cases) — a v1.x ergonomic layer, **not** v1; raw argv stays the semantic core.

## 8. Status (REALIZED v1 — see ADR-018)

**Built and fresh-agent audited** for the v1 fragment (`k4kspec/`, commits `0f9eb9d..63ee151`):
- **Blessed-def semantics** — `lines`/`unlines`/`split`/`contains`/`ascii_*`/`int_of`/`is_decimal`
  etc. are pinned in Rocq as **`backend/Kalgebra.v`** (audited once), matching `lib/algebra.ml`.
- **The I/O shim** (`cli × Rocq`) — realized per footprint (no-file / single-file / variadic),
  reading exactly the declared paths (frame by construction), in `lib/certify.ml`.
- **The elaborator** (`lib/rocq_emit.ml`) — `Ast.spec → .v` (`Input`/`spec_rel`/`run`/generic
  proof/extraction). For v1 (one prover) the prover-independent IR is collapsed (ADR-018).
- **The spec-validation oracle** — the front-end `Eval` oracle (`lib/eval.ml`) is built and is
  used by `certify` to cross-check the certified binary; differential clone-mode is the optional
  `Refdiff` plug.

**Still open:** the **statement-preserving** check on the elaborator (ADR-016 §5); **verified
extraction** / TCB shrinking; the **agent proof backend** (ADR-019) for hard proofs where `run`
differs from the spec; the deferred **argv-grammar sugar**; reinstating the prover-independent IR
when a 2nd prover (ACSL/Lean) is added.
