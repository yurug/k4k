# k4kspec — spec-validation core (v1 WIP, 2026-06-20)

The **reference-free** front-end of k4k v1: parse/represent a k4kspec spec, run it as an
**executable oracle**, and validate it against the author's *intent* — with **no reference
binary required**. Differential testing against a real tool is an *optional* plug (clones only).

This is **not** the certifying back-end (Rocq proof + extraction + certificate); that is
future work. See `../SESSION_STATE.md` for status and `../kb/spec/k4kspec.md` for the language.

## Try it

```sh
dune build @k4kspec/test/runtest                              # unit + round-trip tests -> "ALL OK"
dune exec k4kspec/bin/main.exe -- check examples/kvget.k4kspec # validate a .k4kspec FILE
dune exec k4kspec/bin/main.exe -- check kvget                  # ...or a built-in name
dune exec k4kspec/bin/main.exe -- run   grepf -- an FILE       # execute a spec as its model
dune exec k4kspec/bin/main.exe -- check grepf --ref 'grep -F'  # optional clone diff
```

`check` reports: examples · stability (exhaustiveness / dead-case / anti-vacuity) ·
under-specified dimensions (free channels, for sign-off) · a curated boundary surface.

`check`/`run` accept a `.k4kspec` FILE (parser: `lib/parse.ml`, with `line:col` errors) or a
built-in name. The `examples/*.k4kspec` files are round-trip tested against the trusted AST
specs in `lib/specs.ml`. Surface syntax: `../kb/spec/k4kspec.md` §7.
