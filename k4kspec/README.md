# k4kspec — spec-validation core (v1 WIP, 2026-06-20)

The **reference-free** front-end of k4k v1: parse/represent a k4kspec spec, run it as an
**executable oracle**, and validate it against the author's *intent* — with **no reference
binary required**. Differential testing against a real tool is an *optional* plug (clones only).

This is **not** the certifying back-end (Rocq proof + extraction + certificate); that is
future work. See `../SESSION_STATE.md` for status and `../kb/spec/k4kspec.md` for the language.

## Try it

```sh
dune build @k4kspec/test/runtest                       # unit tests -> "ALL OK"
dune exec k4kspec/bin/main.exe -- check kvget          # validate the non-clone spec
dune exec k4kspec/bin/main.exe -- run   grepf -- an FILE
dune exec k4kspec/bin/main.exe -- check grepf --ref 'grep -F'   # optional clone diff
```

`check` reports: examples · stability (exhaustiveness / dead-case / anti-vacuity) ·
under-specified dimensions (free channels, for sign-off) · an adversarial boundary sweep.

Specs currently live as AST values in `lib/specs.ml` (parser is the next step). Surface
syntax is documented in `examples/` and `../kb/spec/k4kspec.md` §7.
