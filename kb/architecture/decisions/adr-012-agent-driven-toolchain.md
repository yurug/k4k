---
id: adr-012
type: decision
summary: k4k does not select toolchains; the agent does. The agent emits a wrapper script per project that conforms to the verifier wire protocol; k4k just runs it. k4k auto-installs missing tools via user-scoped package managers (opam, uv/pipx, npm, cargo). System-level installs (sudo) require user sign-off.
domain: architecture
last-updated: 2026-05-08
depends-on: [adr-008, adr-009, adr-011]
refines: [adr-008, adr-009]
related: [adr-011, adr-013]
---

# ADR-012: Agent-driven toolchain selection + auto-installation

## Status
**REVISED by ADR-016 (2026-06-19): deferred for v1.** The 2026-06-19 expert panel showed agent toolchain self-selection makes the TCB the union of N kernels + N shims + N extraction paths. v1 therefore **pins one prover (Rocq + extraction to OCaml)**; additional toolchains return later as *audited plugins* (prover backend + I/O shim + statement-preserving elaborator lowering), not stochastic per-project picks. The general principle — k4k carries no built-in selection logic, toolchains are pluggable — stands; the *autonomous per-project selection* is what is deferred. — *Originally:* Accepted (2026-05-08). Refines ADR-008/009: where ADR-008/009 made the verifier and backend pluggable from k4k's perspective, ADR-012 takes the further step of making the toolchain choice itself the agent's decision, not a k4k-side selection rule. Pairs with ADR-011 (autonomous-agent UX) — the user does not see toolchain decisions, the agent makes them per project.

## Context

ADR-008 (verifier-protocol retrofit) removed verifier-specific code from `lib/`: k4k ships only `Verifier_external`, a generic adapter that delegates to a configured executable. v0/v1 still had `k4k.verifier.command` in the user-visible YAML frontmatter — the *user* configured which verifier to run. v2 removes that frontmatter (per ADR-011): the user doesn't pick toolchains.

A first natural reading is that *k4k* picks the toolchain, given the formalized characterization. Round-4 of v2's ambiguity resolution proposed that ("E1: v2 ships Rocq + Frama-C as default Tier-A toolchains; selection logic in `lib/Tool_select`"). The user explicitly rejected this:

> "The underlying model (Claude, GPT...) will know how to use the toolchains: there should be no need for adhoc support for them in k4k. Don't focus on my examples (Rocq, frama-C): they are just examples. For each project, k4k should ask itself what is the best toolchains to use and adapts."

In other words: hardcoding tool-selection logic in `lib/` re-introduces tool-specific code, which the tool-agnostic principle (memorialized in `feedback_tool_agnostic.md`) forbids. The frontier model running as the agent already has world knowledge of every Tier-A toolchain; k4k's role is to faithfully transport that knowledge into running subprocesses, nothing more.

A separate but related concern: the user does not want to manually install tooling. v0/v1 expected the user to `opam install dune` themselves. The user (round-5 E5): "k4k needs to install what's useful." This is a real autonomy bump — k4k provisions its own environment.

## Decision

### 1. The agent picks the toolchain, in the formalization output

The two-run formalization protocol (ADR-005) produces a canonical `D` (formal characterization). v2 extends the schema with two top-level fields the agent must populate:

- `language : string` — the language the implementation is written in (`"rocq"`, `"c"`, `"lean"`, `"rust"`, …). This is the agent's choice for this project, made on the basis of the user's prose.
- `verifier_command : list-of-string` — the command k4k invokes to verify the project. Typically a wrapper script the agent will also generate (e.g. `["./proofs/verify.sh"]`). The script conforms to `kb/external/verifier-protocol.md` — same wire protocol as before.

Both fields are part of the canonical AST and survive the two-run-equivalence check (ADR-005). If the agent's two formalization runs disagree on `language` or `verifier_command`, that's an ambiguity surfaced to the user via a clarification.

### 2. The agent emits the wrapper script

For toolchains that don't natively conform to the verifier wire protocol (raw `coqc` doesn't speak `--workdir / --focus / --output`), the agent generates a thin shell script alongside the project source — e.g. `proofs/verify.sh`. The script translates between the protocol and the native tool. k4k still has zero knowledge of `coqc` / `frama-c` / `lean` / `verus` / `f*`; it just runs whatever script the agent named.

The wrapper script is part of the project's source tree (committed to the user's git repo per ADR-013), so the user can read it, modify it, port it. It's not k4k's secret.

### 3. No reference Tier-A verifier ships in `examples/`

Symmetric with deleting the Tier-C `examples/verifiers/dune-ocaml/` (per ADR-011 / round-5 I2): we don't ship a "canonical Rocq wrapper" either. That would tempt the agent to use it instead of generating one tuned to the project. The agent's job is to write the wrapper from scratch, *for this project*, conforming to `kb/external/verifier-protocol.md`. The protocol document is the only spec the agent needs.

(Editor's note: this is a strong commitment. It means the wire protocol has to be *pristinely* documented, because the agent reads it without the safety net of a worked example. `kb/external/verifier-protocol.md` is therefore part of the prompt context for every formalization pass.)

### 4. k4k auto-installs missing tools — user-scoped only

When the agent's chosen toolchain isn't already installed, k4k attempts installation via **user-scoped package managers**:

- `opam install <pkg>` (current switch, `~/.opam`)
- `uv tool install <pkg>` or `pipx install <pkg>` (`~/.local/share/`)
- `cargo install --locked <pkg>` (`~/.cargo/bin`)
- `npm install -g --prefix=$HOME/.local/share/k4k/npm <pkg>`

These do not require `sudo`. If the relevant package manager is itself missing AND its install path is user-scoped, k4k can install the package manager too (e.g. opam's `bash <(curl ...)` install to `~/.opam`).

System-level package managers (`apt`, `dnf`, `brew`, `pacman`) require `sudo`, so k4k does **not** invoke them. Instead it surfaces a clarification:

> "I need `<pkg>` from `<system-pkg-manager>`. Either run `<command>` yourself, or tell me to proceed with a non-sudo workaround if one exists."

### 5. Upgrades require sign-off; fresh installs do not

Adding a new tool the user doesn't have is additive (no risk of breaking other projects); k4k installs without confirmation. **Upgrading** an existing tool to a newer version may break other projects in the user's environment, so it requires explicit sign-off via a clarification block:

> "I need `coq ≥ 9.1`; you have `8.20.1`. Approve `opam upgrade coq` or tell me to use the older version with a Tier-A degradation proposal."

### 6. Multi-model backend awareness — structural only in v2

The backend wire protocol (ADR-009) gains an optional `--role <orchestrator|prover|implementer|reviewer>` argument. v2 always passes `orchestrator`; backend implementations may ignore the argument (single-model setups) or use it (future multi-model setups that route per role to different models). v2 does not ship per-role routing; the protocol just leaves the seam open for v3+.

Concretely: `kb/external/backend-protocol.md` is updated to document the optional `--role` argument; reference backend examples (claude-code, ollama) accept and ignore it.

### 7. `lib/` carries no tool-installation knowledge specific to any toolchain

Auto-install is implemented as a small `lib/Toolchain_install` module that:
- Probes for the requested binary on `$PATH`.
- If absent, picks the right user-scoped package manager based on the binary's name (a tiny built-in mapping: `coqc` → `opam`, `frama-c` → `opam`, `cargo`-installed Rust tools → `cargo install`, …).
- Runs the install via `Subprocess.run`.
- Records the install in `.k4k/version/<n>/manifest.json`.

This is the *only* k4k-internal code that knows specific tool names. The mapping is short (≤ 30 entries expected) and lives in one file; future tools added by users-of-k4k may need a small entry, but the mapping is data, not logic. (Discussed alternative: ask the agent to emit install commands too. Rejected because installing arbitrary user-suggested commands is a security hole — the mapping bounds the surface.)

## Consequences

**Wins:**
- k4k's `lib/` stays tool-agnostic in the strong sense: zero knowledge of how Rocq or Frama-C or Lean works; only knowledge of how to run a wrapper script that conforms to the wire protocol.
- The agent's world-knowledge of toolchains is leveraged directly. A frontier model knows current best practices (e.g. "for this kind of property, use SSReflect tactics" or "use the WP plugin's RTE extension"); k4k benefits without us encoding any of it.
- Auto-install delivers on the user's "the user only writes in the .k4k file" principle — they're not running `opam install` either.
- The wire protocol documents become first-class artefacts read by the agent; they're now load-bearing in the agent's decision-making, not just the operator's.

**Costs:**
- The protocol docs (`kb/external/verifier-protocol.md`, `kb/external/backend-protocol.md`) must be pristinely written — no implicit assumptions, no "the wrapper is a tiny shell script" hand-waving. The agent reads them cold.
- Two formalization runs need to agree on `language` and `verifier_command` (the canonical-AST equivalence check now includes these fields). If frontier models give plausibly-different toolchain choices for the same spec, that's a real ambiguity the user must resolve.
- The `lib/Toolchain_install` mapping is a small piece of tool-specific code, justified by the security boundary on what install commands k4k will run. Future tools added to that mapping are rare PRs.
- v2 ships no Tier-C example; the conformance suite needs a synthetic stub fixture instead.

**Out of scope for v2:**
- Cross-toolchain compositions (e.g. Rocq spec + Frama-C-verified C library implementing it) — the agent picks a single language per project.
- Toolchain *upgrades* across versions (project pins a toolchain version at version-1 stability; later versions inherit unless the user explicitly approves an upgrade).

## What this means for implementers

- **The formalization output schema gets two new required fields.** `language` and `verifier_command`. Update `lib/Characterization` accordingly; both must round-trip through canonicalization.
- **The gap-step prompt is tier-aware AND toolchain-aware.** It tells the agent: "this project's language is `<language>`; emit code/proofs accordingly; the verifier command is `<verifier_command>`."
- **`lib/Toolchain_install` is the only tool-specific module in `lib/`.** Keep it data-driven (the binary→package-manager mapping is a list, not nested logic). Document the mapping in `kb/external/toolchain-install.md` (new file) for the drift-watch runbook to track.
- **The backend protocol's `--role` argument is optional.** Existing backend executables (`examples/backends/claude-code/`, `examples/backends/ollama/`) gain a no-op acceptance of the flag; old backends without the flag still work (k4k tolerates "unknown argument" rejection from a strict backend by retrying without `--role`).
- **The v2 conformance suite drops the dune-ocaml fixture and gains a synthetic-stub fixture** that demonstrates a wire-protocol-conformant verifier in <50 lines of bash, used only to test schema validation on outputs.

## Relationship to ADR-008 / ADR-009

ADR-008 said: "k4k ships no verifier-specific code; verifiers are external executables conforming to a wire protocol." ADR-012 adds: "k4k also doesn't *select* the verifier — the agent does, per project, by emitting both the toolchain choice and a wrapper script that conforms to the protocol." The wire protocol stays unchanged; what's new is who picks which executable to invoke.

ADR-009 said: "k4k ships no backend-specific code; backends are external executables." ADR-012 adds the optional `--role` argument as structural prep for v3+ multi-model routing.
