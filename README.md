# k4k — KISS for KISS

If you build a KISS program, keep its agentic development stupidly simple:
**sign a specification, and prove one theorem: the program does one thing and
does it well.**

k4k is a spec-validation and certification harness for KISS programs,
POSIX-like command-line tools whose observable behavior is fully determined by
`argv` and file contents. You write a short observational specification in the
**k4kspec** language; k4k validates it, you *sign* it, and k4k produces a
machine-checked certificate that a generated implementation satisfies it, with
a manifest that names exactly what you are trusting.

> **Status: experimental.** k4k is part of a broader experiment on
> [software engineering in the agent era](https://yann.regis-gianas.org/en/),
> alongside [rocqeteer](https://github.com/yurug/rocqeteer),
> [agentic-dev-kit](https://github.com/yurug/agentic-dev-kit) and the essays
> that report on them. It is usable today on programs within its scope, and
> its interfaces will move.

## The idea

Coding agents make production cheap; validation is what stays hard. For a
KISS program, validation can be made stupidly simple too, because the whole
demand fits in a specification a human can read, sign, and a machine can
check. k4k enforces that division of labor:

- **The human is the sole writer and signer of the spec.** Agents may
  *propose* spec drafts and revisions (`k4k propose`, `k4k revise`), but
  nothing is certified that a human did not sign, and signing refuses to
  proceed while any observable dimension is left unconstrained and
  unacknowledged.
- **The machine owns the proof.** Certification elaborates the spec to a Rocq
  theorem, checks it, extracts the program, and cross-checks the binary
  against the spec's own executable oracle.

KISS is a scope, not a doctrine: plenty of systems are intrinsically complex
and need their depth. k4k works the proving ground where the process runs
end-to-end with strong guarantees.

## Five-minute demo

A spec is a few lines. `upper` prints its ASCII-uppercased argument:

```
interface cli "upper":
  writes: nothing
cases on argv:
  when len(argv) != 1: exit 2 ; stderr: one nonempty line ; stdout: ""
  otherwise:
    stdout: ascii_upper(argv[0]) ++ "\n"
    stderr: ""
    exit:   0
examples:
  argv=["hello"] -> stdout="HELLO\n" exit=0
  argv=["aB3z!"] -> stdout="AB3Z!\n" exit=0
  argv=[] -> exit=2
  argv=["a","b"] -> exit=2
```

Validate it:

```
$ k4k check upper.k4kspec
[examples] 4/4 passed
[stability]
  exhaustiveness (static): OK (otherwise present)
  exhaustiveness (swept 11 inputs): OK (all matched a case)
  anti-vacuity: OK (no fully-unconstrained channel)
[under-specified dimensions]
  case #0  stderr : free (one-nonempty-line)
```

Try to sign it. k4k refuses until you acknowledge what you left open:

```
$ k4k sign upper.k4kspec
REFUSE: this spec leaves 1 observable dimension(s) unconstrained.
Signing acknowledges them as INTENDED. Re-run with --ack-underspec to sign.

$ k4k sign upper.k4kspec --ack-underspec
signed: upper.k4kspec -> v1  (upper.k4k/signatures/v1.sig)
```

Certify. This is the theorem being proved and checked for real (`coqc` must
be on your `PATH`):

```
$ k4k certify upper.k4kspec
coqc: proof CHECKED (exit 0; algebra from audited-once Kalgebra.v), extraction done
certificate gate: statement pinned (correct : forall i, spec_rel i (run i)); Print Assumptions closed
compiled the certified binary
binary MATCHES spec on 15/15 inputs
certificate: upper.k4k/certificates/v1/certificate.md
CERTIFY: OK
```

Eight built-in specs ship for exploration (`k4k list`): grepf, cutf, catf,
kvget, bsort, partition, usort, grepsort. `k4k run <spec> -- <args>` executes
any spec as its own reference model; `k4k emit <spec>` prints the elaborated
Rocq statement.

## What the certificate means, exactly

The pipeline is deterministic: elaborate the signed spec against a blessed,
audited-once value algebra (`k4kspec/backend/Kalgebra.v`); check a
non-vacuous theorem `correct : forall i, spec_rel i (run i)` with `coqc`
(`Print Assumptions` must come back closed, no axioms, no `Admitted`);
extract to OCaml; compile with a thin I/O shim; run the binary against the
spec's executable oracle on the full validation sweep; record a certificate
and a TCB manifest in the spec's `.k4k/` ledger.

What you trust, and it is written in every manifest: Rocq's kernel, Rocq's
extraction, the OCaml compiler, the audited-once algebra, the I/O shim, and
the elaborator from k4kspec to Rocq. What you do not have to trust: the agent
that drafted the spec or the proof, and the implementation itself.

Agent-driven proving exists behind the same gate: `k4k certify-agent` lets an
LLM (`$K4K_PROOF_CMD`) drive the prover, and nothing it produces is accepted
unless `coqc` checks it under the same closed-assumptions rule.

## Roadmap

- **Backend abstraction.** The certification core is being kept abstract over
  execution backends. The first target backend is
  [rocqeteer](https://github.com/yurug/rocqeteer), a certified pipeline from
  effectful Rocq programs to idiomatic OCaml 5, so that certified k4k tools
  get real file and stdin/stdout behavior with proven semantics instead of a
  trusted shim.
- **Local explainability.** An experiment measuring module cohesion as the
  minimal length of a correct explanation of the module's role, hosted here,
  feeding the blog series.

## Build

```
dune build            # OCaml >= 5.3, stdlib-only
dune exec k4kspec/test/test_k4kspec.exe   # ALL OK expected
dune install          # installs the k4k binary
```

Certification additionally needs the Rocq prover on `PATH` (`opam install
coq` installs the 9.x compatibility binaries, including `coqc`).

## License

MIT. See [`LICENSE`](LICENSE).
