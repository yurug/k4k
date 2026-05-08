# Reference verifier — OCaml + dune projects (Tier C)

Standalone executable conforming to k4k's verifier wire protocol
(see `kb/external/verifier-protocol.md`).

## ⚠️ Tier-C example, not the canonical default

Per `kb/domain/prd.md` (v2) and the verification-tier hierarchy: this
verifier is a **Tier-C** example — it establishes property statuses
solely from a passing test suite. It is **not** what k4k aims for by
default. The canonical default is Tier A (full formal verification —
Rocq with extraction to OCaml; Frama-C/ACSL on C; Lean; Verus; F*),
where the verifier runs `coqc` / `frama-c -wp` / etc. against
machine-checked artifacts.

This example exists for two reasons:
1. To demonstrate how *any* tier is reachable through the wire
   protocol (the protocol itself doesn't know what tier the verifier
   targets).
2. To support test scenarios where Tier-A toolchains aren't available
   in CI (the conformance suite at `test/conformance/` uses it).

If a property genuinely cannot reach Tier A and Tier B, k4k's
trade-off-negotiation flow may end up using a Tier-C verifier like
this — but only with explicit user sign-off recorded in the `.k4k`
file. See the PRD's verification-tier table.

## What it does

- Runs `dune build @runtest --force --display=quiet --root <workdir>` on the
  target source tree.
- Parses alcotest output lines `[OK|FAIL]  <suite>  <num>  <test_name>.`
- Maps test names matching `P<7hex>_<slug>` to property statuses:
  - `[OK]`   -> `established`
  - `[FAIL]` -> `contradicted`
  - properties in `--focus` not seen -> `unknown`
- Emits `unconventional-test-name` warnings for tests not matching the
  `P<id>_<slug>` convention.
- Writes the result JSON atomically to the path given by `--output`.

## How to plug it in

Set `k4k.verifier.command` in your `<file.k4k>` frontmatter:

```yaml
---
k4k:
  version: 1
  class: cli
  verifier:
    command: ["_build/default/examples/verifiers/dune-ocaml/main.exe"]
    timeout_s: 300
---
```

Or, for a project that has installed the binary system-wide:

```yaml
    command: ["verify_dune_ocaml"]
```

## Output schema

See `kb/external/verifier-protocol.md` for the canonical schema. In short:

```json
{
  "by_property": { "P1234567": "established", "P89abcde": "contradicted" },
  "raw_exit_code": 0,
  "duration_ms": 1234,
  "warnings": [
    { "kind": "unconventional-test-name", "message": "weird_test_name" }
  ]
}
```

## Known limitations

- Expects the test runner output to be alcotest-formatted. Other runners
  (`ounit2`, `qcheck-junit`, raw `printf`-style harnesses) are not
  understood.
- Dedup policy: if multiple tests share a property ID, `contradicted`
  wins over `established`.
- Inherits the parent process's environment and `PATH` for locating
  `dune`.
