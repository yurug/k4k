# Reference verifier — OCaml + dune projects

Standalone executable conforming to k4k's verifier wire protocol
(see `kb/external/verifier-protocol.md`).

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
