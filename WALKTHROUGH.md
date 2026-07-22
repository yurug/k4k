# k4k — walkthrough

A full session, from an unsigned spec to a certificate, with the outputs you
should expect. Run on 2026-07-22 with Rocq 9.1.0 and OCaml 5.3.0; trimmed
only where marked.

## 0. Build

```
$ dune build && dune install
$ k4k list
grepf
cutf
catf
kvget
bsort
partition
usort
grepsort
```

## 1. Check

`check` validates a spec: the examples run against the spec's own executable
model, exhaustiveness and dead cases are analyzed, anti-vacuity is enforced
(a spec that constrains nothing certifies nothing), and an adversarial sweep
summarizes the validation surface per case.

```
$ k4k check upper.k4kspec
=== k4kspec check: upper ===

[examples] 4/4 passed

[stability]
  exhaustiveness (static): OK (otherwise present)
  exhaustiveness (swept 11 inputs): OK (all matched a case)
  dead cases (heuristic, over sweep): none
  anti-vacuity: OK (no fully-unconstrained channel)

[under-specified dimensions]  (content agent-authored, NOT certified — intended?)
  case #0  stderr : free (one-nonempty-line)

[validation surface]  (curated; full sweep = 11 inputs)
  by case (one representative per distinct behavior):
    case #0  [len(argv) != 1]  — 7 input(s)
        -> exit=2 stdout="" stderr=~one-nonempty-line   e.g. argv=[] files={}
    case #1  [otherwise]  — 4 input(s)
        -> exit=0 stdout="HELLO\n" stderr=""   e.g. argv=["hello"] files={}
```

Note the `[under-specified dimensions]` report: case #0 leaves stderr's
content free. k4k will not let that pass silently.

## 2. Run the spec as its own model

Any spec is executable before any implementation exists:

```
$ k4k run upper.k4kspec -- hello
HELLO
[k4kspec] upper: case #1 [otherwise] -> exit=0, stdout=6 bytes, stderr=pinned
```

## 3. Sign

Signing is the human act. It freezes the exact spec bytes as a version. It
refuses while under-specification is unacknowledged:

```
$ k4k sign upper.k4kspec
  case#0 stderr : free (one-nonempty-line)
REFUSE: this spec leaves 1 observable dimension(s) unconstrained (listed above).
Signing acknowledges them as INTENDED. Re-run with --ack-underspec to sign.

$ k4k sign upper.k4kspec --ack-underspec
signed: upper.k4kspec -> v1  (upper.k4k/signatures/v1.sig)
```

## 4. Certify

Certification refuses unsigned specs (`--unsigned` exists for development
runs and says so). On a signed spec:

```
$ k4k certify upper.k4kspec
coqc: proof CHECKED (exit 0; algebra from audited-once Kalgebra.v), extraction done
certificate gate: statement pinned (correct : forall i, spec_rel i (run i)); Print Assumptions closed
compiled the certified binary
binary MATCHES spec on 15/15 inputs
wrote upper.tcb.md ; certified binary at /tmp/k4k_certify/upper
certificate: upper.k4k/certificates/v1/certificate.md
CERTIFY: OK
```

The certificate ledger (`upper.k4k/certificates/v1/`) now holds the
certificate and the TCB manifest naming every trust assumption. `k4k status
upper.k4kspec` summarizes signature validity, waivers, and certificates.

## 5. Where the Rocq goes

`k4k emit upper.k4kspec` prints the elaborated Rocq statement and `run`
function that `certify` checks, stated against the audited-once
`k4kspec/backend/Kalgebra.v`.

## Agent-assisted flows

- `k4k propose <name> <intent>` and `k4k revise <file> <request>` let an
  agent draft or amend a spec; drafts are gated by parse+check and recorded
  in a decision journal. The human remains the sole signer.
- `k4k certify-agent [--structured|--compositional] <spec>` lets an LLM
  (`$K4K_PROOF_CMD`) drive the prover; acceptance is still `coqc` with closed
  assumptions, nothing less.
