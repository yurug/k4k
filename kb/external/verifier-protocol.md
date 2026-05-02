---
id: external.verifier-protocol
type: spec
summary: The wire protocol between k4k and any external verifier. k4k itself ships zero verifier-specific code; users plug in any verifier that satisfies this protocol.
domain: external
last-updated: 2026-05-02
depends-on: [glossary, spec.api-contracts, spec.data-model]
refines: [spec.api-contracts]
related: [adr-008, conventions.testing-strategy]
---

# Verifier Protocol

## One-liner

A verifier is **any executable** that, when invoked with the documented command-line interface, reads a target source tree and writes a JSON result file describing per-property status. k4k spawns the executable, parses the result, and treats the output as the source of truth — no other coupling.

## Scope

The contract a verifier must satisfy. k4k's `lib/Verifier_external` is the only adapter required to invoke verifiers; per-tool code (test parsers, exit-code maps, output regexes) lives in the verifier executable itself, not in k4k.

A *reference verifier* implementing this protocol for OCaml + dune ships at `examples/verifiers/dune-ocaml/` as a worked example; it is not part of k4k's binary.

## Why a wire protocol (not an OCaml signature)

`Verifier.S` (the OCaml signature, retained for type-level wiring inside k4k) is satisfied by **one** concrete adapter (`Verifier_external`) that delegates everything beyond JSON parsing to a configured executable. The OCaml signature is internal scaffolding; the wire protocol below is the **public contract** users target when adding verifier support.

Rationale recorded in `architecture/decisions/adr-008-verifier-protocol.md`. Short version: k4k's KISS thesis demands the harness itself be POSIX-shaped; carrying alcotest-output regexes and dune-specific exit-code semantics inside `lib/` violated that thesis.

## Invocation

k4k spawns the verifier as:

```
<command> [<extra-args>...] \
  --workdir <abs-path-to-source-tree> \
  --focus <prop-id-1> [<prop-id-2> ...] \
  --output <abs-path-to-result.json>
```

- `<command>` and any prefix `<extra-args>` come from the interaction file's frontmatter `k4k.verifier.command` (a list of strings) — see `spec/config-and-formats.md`.
- `--workdir` is the directory containing the target program's source. The verifier may read freely under this path; it must NOT write outside `<workdir>` and `<output>`'s parent directory.
- `--focus` lists the property IDs the harness expects status for. May be empty (interpret as "all known properties"). The verifier MAY report status for properties not in `--focus` (extras are ignored by k4k); MUST report status for every ID in `--focus` (missing IDs are taken as `unknown`).
- `--output` is the destination path for the result JSON. The verifier writes atomically (tmp + rename) to avoid the harness reading a partial file.

`stdin` is closed. The verifier inherits the harness's environment (so verifier-specific env vars work without forwarding by k4k).

## Result file (`<output>`)

Single JSON object. Schema:

```json
{
  "by_property": { "<prop-id>": "<status>", ... },
  "raw_exit_code": <int>,
  "duration_ms": <int>,
  "warnings": [
    { "kind": "<warn-id>", "message": "<text>", "detail": <any-json> }
  ]
}
```

- `by_property`: map from property ID to status `"established" | "contradicted" | "unknown"`. Required.
- `raw_exit_code`: the verifier's own internal tool exit code, for audit logs. Required.
- `duration_ms`: total verifier wall-clock in milliseconds. Required.
- `warnings`: zero or more advisory entries. Optional. Each entry's `kind` SHOULD use a stable identifier so log readers can group them; e.g. `"unconventional-test-name"`, `"build-warning"`. `detail` is opaque JSON.

The result file MUST be valid UTF-8 JSON. k4k uses Yojson to parse; trailing whitespace and a trailing newline are tolerated.

## Verifier exit codes (the *process* exit, not `raw_exit_code`)

| Exit | Meaning                                                                      | k4k mapping                          |
|------|------------------------------------------------------------------------------|--------------------------------------|
| 0    | Result file written and valid                                                | Continue with the parsed result      |
| 1    | Tool error (e.g. compiler missing, broken project structure)                 | `EVERIFIER_TOOL_ERROR`               |
| 130  | Killed by SIGINT                                                             | `Tool_error "interrupted"`           |
| any other | Same as 1, with the exit code preserved in the harness JSONL log        | `EVERIFIER_TOOL_ERROR`               |

If exit is 0 but the result file is missing or unparseable: `EVERIFIER_TOOL_ERROR`.

## Wall-clock budget

- Per-invocation cap: configured via `k4k.verifier.timeout_s` in the interaction file (default 60 s). On timeout, k4k kills the verifier and emits `EVERIFIER_TOOL_ERROR`.
- The harness's per-gap-step wall-clock measurement is the verifier's reported `duration_ms` (NOT the harness's outer stopwatch — they should agree closely).

## Non-functional contract

- **Determinism.** Given the same workdir contents and the same focus list, two invocations of the same verifier must produce the same `by_property` map. The verifier MAY emit different `duration_ms`/`warnings`. Determinism on `by_property` is what the harness's NF6 contract leans on.
- **Read-only on the user's source.** The verifier may write only to `<output>`'s parent and to ephemeral build directories that the user's `.gitignore` excludes (the user's responsibility, not k4k's). Writes to the user's tracked source tree are a contract violation.
- **No interaction.** The verifier MUST run non-interactively. No prompts on stdin. No TTY assumptions.

## Configuration in the interaction file

Required, under `k4k.verifier`:

```yaml
---
k4k:
  version: 1
  class: cli
  verifier:
    command: ["./scripts/verify.sh"]
    timeout_s: 60
---
```

The CLI flag `--verifier '<command-string>'` overrides `command` for one run. `timeout_s` is overridden by `--verifier-timeout`. Defaults: `timeout_s = 60`. There is no default for `command` — the interaction file MUST declare one (failing this is `EUNSTABLE`, with a clarification appended).

## Reference verifier (worked example)

`examples/verifiers/dune-ocaml/` ships a reference implementation suitable for OCaml + dune projects. It:
- Runs `dune build @runtest --force --display=quiet --root <workdir>`.
- Parses alcotest output (lines matching `^\s*\[(OK|FAIL)\]\s+\S+\s+\d+\s+(P\w+)_.*\.\s*$`).
- Maps `[OK]` → `established`, `[FAIL]` → `contradicted`, properties in `--focus` not seen → `unknown`.
- Emits `unconventional-test-name` warnings for tests not matching the convention.

It is a **standalone OCaml binary** in the same dune-project as k4k, but its source lives outside `lib/` and `bin/` to make the boundary explicit. To use it, set `k4k.verifier.command` to the installed binary's path.

## Agent notes

> **The protocol is the contract.** Any change to `--workdir`/`--focus`/`--output` semantics, or to the result JSON schema, is a breaking change requiring a `k4k.version` bump in the interaction file. Adding optional fields to the result is non-breaking; renaming or removing required fields is breaking.
>
> **k4k carries no verifier-specific knowledge.** Adding Rocq, Frama-C, AFL, Verus, or anything else does not touch k4k's source. It is a new executable conforming to this contract, packaged or distributed separately.

## Related files

- `architecture/decisions/adr-008-verifier-protocol.md` — the decision record
- `architecture/decisions/adr-004-verifier-extension.md` — partially superseded by ADR-008
- `spec/api-contracts.md` — the OCaml-internal `Verifier.S` signature that `Verifier_external` satisfies
- `spec/config-and-formats.md` — the interaction-file schema including `k4k.verifier`
- `properties/non-functional.md#NF6` — determinism contract this protocol leans on
