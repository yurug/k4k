---
id: external.toolchain-install
type: external
summary: Registry of binary names → user-scoped package managers used by `lib/Toolchain_install.ensure` to auto-install missing tools the agent picks per project. Bounded surface; security boundary on what install commands k4k will run.
domain: external
last-updated: 2026-05-08
depends-on: [adr-012, adr-011]
refines: []
related: [external.backend-protocol, external.verifier-protocol]
---

# External: toolchain-install registry

## Why this layer exists

Per ADR-012 §4–§7: k4k auto-installs missing tools so the user can stay inside the `.k4k` file (no `opam install …` ceremony). But "install whatever the agent suggests" is a security hole. The registry below bounds what k4k will run on the user's machine to a hand-curated mapping from binary names to user-scoped package managers (no `sudo`).

Tool-name knowledge in `lib/` is contained to one file (`lib/toolchain_install.ml`) and one data structure (the `mapping` list). Adding a tool is a one-line PR; no new logic. This is the only place in the codebase per **P23** that may reference toolchain binaries by name.

## How the module behaves at runtime

`Toolchain_install.ensure ~binary:"<name>"` returns one of four outcomes:

| Outcome | Meaning |
|---|---|
| `Already_present { binary; version }` | The probe (`command -v <bin>` + `<bin> --version`) succeeded. No install attempted. |
| `Installed { binary; version; via }` | Probe failed; the registered package manager ran successfully; the binary now resolves. `via` is the manager name (`opam` / `cargo` / …). |
| `Needs_user_consent { binary; reason; suggested_command }` | The relevant package manager either requires `sudo` (the `System` variant) or is itself missing in user-scope and bootstrap is judged unsafe. k4k does not run anything; the watcher daemon (batch 2) surfaces this as a `## k4k:clarification:<ts>` block. |
| `Failed msg` | The package manager ran but exited non-zero (or, for the rare success-but-still-missing case, the binary didn't appear on `$PATH`). The watcher daemon surfaces this so the user can investigate. |

The probe + install flow is idempotent: re-invoking `ensure` after a successful `Installed` returns `Already_present`.

A test-only env var, `K4K_TOOLCHAIN_INSTALL_STUB=1`, makes `ensure` consult an in-memory stub table seeded by `test_set_stub_outcome` instead of running subprocesses. Production runs leave it unset.

## The registry

The current registry (≤ 30 entries) is the literal value of `Toolchain_install.mapping`. To audit what k4k may install on your machine, read that list.

| Binary | Package manager | Notes |
|---|---|---|
| `coqc` | `opam` (`coq`) | Tier-A: Rocq / Coq |
| `coqtop` | `opam` (`coq`) | |
| `coq-extraction` | `opam` (`coq`) | |
| `frama-c` | `opam` (`frama-c`) | Tier-A: WP plugin used by ACSL |
| `lean` | `Other_user_install` (`elan`) | Lean 4; bootstrapped via elan |
| `lake` | `Other_user_install` (`elan`) | Lean build tool |
| `verus` | `cargo install --locked verus` | Tier-A: Rust verifier |
| `fstar.exe` | `System` (`fstar`) | sudo-only; surfaced to user |
| `dune` | `opam` (`dune`) | Tier-A backstop for OCaml |
| `ocamlfind` | `opam` (`ocamlfind`) | |
| `ocaml` | `System` (`ocaml`) | sudo-only |
| `z3` | `pipx` (`z3-solver`) | SMT |
| `cvc5` | `Other_user_install` | binary tarball |
| `ruff` | `uv tool install ruff` | Python linter |
| `mypy` | `uv tool install mypy` | Python types |
| `rustup` | `Other_user_install` | bootstraps cargo |
| `cargo` | `Other_user_install` (`rustup`) | |
| `tsc` | `npm` (`typescript`) | TypeScript compiler |
| `cotype` | `Other_user_install` | k4k's interaction-file concurrency dep (ADR-010) |

Entries are illustrative. Read `Toolchain_install.mapping` in `lib/toolchain_install.ml` for the source of truth.

## Adding a new entry

1. Edit `Toolchain_install.mapping` in `lib/toolchain_install.ml`. One line.
2. Add a row to the table above. One line.
3. Run `dune runtest --force`. The data-driven invariant (`Toolchain_mapping_is_data_driven`) checks no duplicate keys and `≤ 30` entries.

No logic edit is necessary. If you find yourself wanting to write `if binary = "<x>" then …` outside `lib/toolchain_install.ml`, stop — that violates **P23** and ADR-012 §7. Express the variation as a different `package_manager` constructor instead.

## `package_manager` variants

```ocaml
type package_manager =
  | Opam              of string  (* opam package name *)
  | Pipx              of string
  | Uv_tool           of string
  | Cargo             of string
  | Npm               of string  (* HOME-scoped prefix: ~/.local/share/k4k/npm *)
  | System            of string  (* sudo-only: triggers Needs_user_consent *)
  | Other_user_install of string (* generic curl|sh user install hint *)
```

`Opam | Pipx | Uv_tool | Cargo | Npm` are the user-scoped "k4k may run this without asking" set. `System` and `Other_user_install` always go through `Needs_user_consent`; the suggested-command hint helps the user decide.

## Drift watch

This file and `Toolchain_install.mapping` must stay in sync. The weekly drift-watch runbook covers:

- Every entry in the registry has a row in this file's table.
- Every row in the table corresponds to a registry entry.
- The `≤ 30` size cap is respected.
- No tool-name mention has leaked into a non-`toolchain_install.{ml,mli}` `lib/` file (a check approximating **P23**'s lint strategy).

Drift here is high-impact: the security boundary on what k4k installs depends on it.

## Relationship to other docs

- **ADR-012**: defines the data-driven boundary; this file is the data.
- **ADR-011**: the user never sees toolchain decisions — they're auto-resolved or surfaced as a clarification when consent is needed.
- **`kb/external/verifier-protocol.md`**: once a tool is installed, the agent's wrapper script is what k4k actually invokes. This file's registry only governs which binaries k4k will probe-and-install.
- **`kb/properties/functional.md#P23`**: the property this module is designed to embody.
