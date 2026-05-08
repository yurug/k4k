---
id: runbooks.test-environment
type: procedure
summary: Test-only environment knobs k4k honors. Each is OFF by default, has zero production effect, and exists so the test suite can drive the binary deterministically through edge cases that are hard to provoke from the outside.
domain: runbooks
last-updated: 2026-05-02
depends-on: [glossary, spec.api-contracts]
refines: []
related: [conventions.testing-strategy, properties.functional, properties.non-functional]
---

# Test Environment Knobs

## One-liner

The k4k binary honors a handful of `K4K_*` environment variables that the test suite uses to drive deterministic edge-case scenarios. Production users never set them; if any are set in production, k4k still runs but you should know what they do.

## Scope

Test instrumentation only. None of these are part of the public CLI contract (`spec/api-contracts.md`). They are nevertheless **documented k4k surface** because they appear in the binary's source and a future contributor reading `bin/main.ml` needs to know what they do.

## Knobs

### `K4K_BACKEND_COMMAND=<shell-style argv>`
**Purpose:** in production, this is how the operator points the
watcher at an agent backend conforming to
`kb/external/backend-protocol.md`. The string is parsed by
`Backend_resolve.split_command` (whitespace-separated; double-quoted
segments group; `\"` escapes a quote inside a quoted segment; no
`$VAR` / `~` expansion). The resulting argv is the leading prefix
of every `Backend_external.invoke` call (k4k appends `--purpose`
/ `--prompt-file` / `--budget` / `--output`).

`K4K_BACKEND_COMMAND` is the OPERATOR-level seam. The user UX
remains "edit the .k4k file"; the operator launches the watcher
once with this env var set in their shell or systemd unit.
**Default:** unset → `Backend_resolve` falls back to
`K4K_STUB_RESPONSES`, then to the unconfigured-fallback closure
that yields `Tool_error` on every call (the watcher logs
`agent.unconfigured` once and continues polling).
**When the binary itself reads this:** at watcher startup
(`Backend_resolve.resolve`, called once per run from
`Watcher_loop.run`).
**Production effect:** this IS the production effect — the watcher
cannot reach an external backend without it (or
`K4K_STUB_RESPONSES` for tests).

### `K4K_LIVE=1`
**Purpose:** opt into real `claude` and real `dune` invocations during a test run.
**Default:** unset. The v2 watcher resolves the agent backend through `Backend_resolve.resolve` (`K4K_STUB_RESPONSES` → `K4K_BACKEND_COMMAND` → unconfigured fallback); set `K4K_LIVE=1` only in tests that explicitly opt into the example backends under `examples/backends/{claude-code,ollama}/`. The verifier is configured per-D via `Characterization.verifier_command` (ADR-012 §1) — the agent emits the wrapper script per project; k4k ships no reference verifier example.
**When the binary itself reads this:** never directly in v2. The flag is a test harness convention to skip live-only scenarios.
**Production effect:** none unless explicitly set; users who want to run k4k for real *do* want this set.

### `K4K_STUB_RESPONSES=<path-to-json>`
**Purpose:** load canned agent responses for `Backend_stub`. Each entry: `{purpose, trigger, payload}` (per Q3.3). Round-robin within `purpose` if multiple match.
**Default:** unset → `Backend_stub` returns `Tool_error "stub: no canned response for prompt"`. Production binary errors with `EAGENT_UNAVAILABLE` when `K4K_LIVE` is unset and `K4K_STUB_RESPONSES` is unset.
**When read:** at every `Backend_stub.invoke` call.
**Production effect:** none unless explicitly set. Power users could in principle drive k4k against a fully canned response file for fully reproducible runs — undocumented but possible.

### `K4K_STUB_SLOW=<seconds>`
**Purpose:** inject a per-call sleep into `Backend_stub` so signal-handling tests have a deterministic in-flight window. Used by `NF1_sigint_during_agent_exits_within_5s` and friends.
**Default:** unset → no sleep.
**When read:** every `Backend_stub.invoke` call sleeps `<seconds>` before returning, regardless of trigger match.
**Production effect:** none — production never uses `Backend_stub`.

### `K4K_FAULT_INJECT_ENOSPC=<path-pattern>`
**Purpose:** simulate disk-full during atomic writes for `T5_disk_full_during_atomic_write`. Substring match on the destination path.
**Default:** unset → no fault injection.
**When read:** every `Persist.atomic_write` checks the env var; if set and the path matches, the tmp file is created, then deleted (rollback), and `E_disk_full` is raised. Production code path is fully exercised; only the rename is short-circuited.
**Production effect:** none unless explicitly set. If a curious user *did* set it, they'd see disk-full errors on writes matching their pattern — not destructive, just noisy.

### `K4K_SYNTH_ESTABLISHED=<space-separated-ids>`
**Purpose:** drive the synthetic verifier stub
(`test/conformance/fixtures/synthetic-verifier.sh`) used by the v2
conformance suite. Property IDs in the list emit
`status: established`; everything else emits `status: unknown`.
**Default:** unset → no IDs are established (every focus id is `unknown`).
**When the binary itself reads this:** never. This env is read only by
the synthetic stub script; production k4k does not consult it.
**Production effect:** none — production never invokes the stub.

### `K4K_TOOLCHAIN_INSTALL_STUB=1`
**Purpose:** activate the in-memory stub table inside
`lib/Toolchain_install` (per ADR-012 §7). When set, `ensure ~binary`
returns the outcome seeded by `Toolchain_install.test_set_stub_outcome`
instead of probing `$PATH` or running a package manager. Used by
watcher startup tests so they don't actually install opam/etc.
**Default:** unset → real probe + real installs (production behavior).
**When the binary itself reads this:** every `Toolchain_install.ensure`
call.
**Production effect:** none unless explicitly set; the stub table is
empty by default so any `ensure` call returns `Failed` and the watcher
aborts at startup — undesirable in production, perfectly safe.

### `K4K_TEST_TRADEOFF_AUTOAPPROVE=<resolution>`
**Purpose:** short-circuit the [`Tradeoff_flow.propose_and_wait`]
polling loop in tests so [`S3_tradeoff_proposal_signed_off`] does
not need a second cotype client to write the user's reply. Accepted
values: `tier-b` (or `b`), `tier-c` (or `c`), `reject:<reason>`,
`timeout`. The watcher splices the proposal block into the file
exactly as it would in production, then resolves the proposal to
the configured outcome instead of waiting for an inline reply.
**Default:** unset → real cotype-mediated polling.
**When read:** every [`Tradeoff_flow.propose_and_wait`] call.
**Production effect:** none unless explicitly set.

### `K4K_TEST_TRACE_WRITES=<path-to-trace-file>`
**Purpose:** record every filesystem write k4k performs through `Persist`, one path per line. Used by `NF4_state_confinement_envelope` to assert all writes fall under allowed paths.
**Default:** unset → no tracing.
**When read:** `Persist.atomic_write` and `Persist.append_jsonl_line` append the destination path to `<path-to-trace-file>` if the env is set.
**Production effect:** none unless explicitly set; if set, it just creates a trace file the user can inspect.

## Test-only CLI flags

### `--exit-on-stable`
**Purpose:** make `bin/main.ml`'s watcher loop return after the first
state transition (stable snapshot OR clarification appended), so
integration tests don't have to send SIGTERM to inspect post-stability
state. Per ADR-011 §2 the production loop runs until signal.
**Default:** unset (operator-only flag).
**When read:** at every iteration of `Watcher_loop.one_tick`.
**Production effect:** none — production users never pass it. Visible
in `--help` output but documented as test-only.

### `--exit-on-done`
**Purpose:** make `bin/main.ml`'s watcher loop return once the
in-flight version completes (state `Done`) or rolls back. Used by
the v2 batch-3 S1 / S5 integration tests to drive the watcher
through a full version-1 lifecycle without SIGTERM.
**Default:** unset (operator-only flag).
**When read:** at every iteration of `Watcher_loop.one_tick` after a
stable spec snapshot is observed.
**Production effect:** none — production users never pass it.

### `--max-versions=<N>`
**Purpose:** make `bin/main.ml`'s watcher loop return after `N`
versions have completed (state `Done`). Used by integration tests
that must drive the watcher through multiple consecutive versions
deterministically — e.g. [`P22b_v1_to_v2_picks_up_user_edits`],
which validates that a user edit applied to the file mid-v1 surfaces
during v2's formalization.
**Default:** unset → no cap.
**When read:** at every iteration of `Watcher_loop.on_stable` after
a `Done` outcome.
**Production effect:** none unless explicitly set. Setting it in
production is harmless: the watcher exits cooperatively after `N`
completed versions.

## Properties enforced

- **All knobs default to OFF.** Production behavior is exactly the same with the env var unset as it would be without the code path existing at all. Asserted by `NF4_trace_disabled_by_default` and the absence of any `Sys.getenv "K4K_*"` calls in production paths beyond the explicit five enumerated here.
- **No knob bypasses a security or correctness property.** `K4K_FAULT_INJECT_ENOSPC` triggers a real rollback path that already exists for genuine ENOSPC; `K4K_TEST_TRACE_WRITES` only observes writes; the others modify only stub-or-test behavior.
- **The set is closed.** Adding a new `K4K_*` knob requires updating this file *first*. No silently-honored env vars.

## Code-coverage recipe

`lib/dune` declares `(instrumentation (backend bisect_ppx))`; the
opam manifest carries `bisect_ppx` as a `with-test` dependency.
Coverage is opt-in (does not affect normal `dune test` runs):

```bash
opam install bisect_ppx
dune runtest --instrument-with bisect_ppx --force
bisect-ppx-report html             # → _coverage/index.html
bisect-ppx-report summary          # one-line per-module digest
```

The Phase-5 audit-checklist target is **≥ 80% line coverage on
`lib/`**. Re-run after every batch that adds significant
production code.

## Why these are documented in the meta KB (`kb/`) rather than per-target (`.k4k/`)

These are knobs of **k4k itself**. The interaction file's user does not see or care about them. They are the responsibility of contributors maintaining k4k.

## Related files

- `spec/api-contracts.md` — the public CLI contract (which deliberately excludes these env vars)
- `properties/non-functional.md#NF4` and `#NF5` — measurement procedures relying on these knobs
- `external/backend-protocol.md` — how external backends differ from `Backend_stub`
