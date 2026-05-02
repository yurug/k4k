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

### `K4K_LIVE=1`
**Purpose:** opt into real `claude` and real `dune` invocations during a test run.
**Default:** unset → `Backend_stub` and (when configured) `Verifier_stub` are used; `Backend_claude` and `Verifier_external` (against the `examples/verifiers/dune-ocaml/` reference binary, which runs real `dune`) are still used for any test that explicitly requests them (e.g. `S1_echo_first_run_e2e` always uses the reference verifier).
**When the binary itself reads this:** `bin/main.ml` selects `Backend_claude` over `Backend_stub` when set. Test harness code reads it to skip live-only scenarios when unset.
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

### `K4K_TEST_TRACE_WRITES=<path-to-trace-file>`
**Purpose:** record every filesystem write k4k performs through `Persist`, one path per line. Used by `NF4_state_confinement_envelope` to assert all writes fall under allowed paths.
**Default:** unset → no tracing.
**When read:** `Persist.atomic_write` and `Persist.append_jsonl_line` append the destination path to `<path-to-trace-file>` if the env is set.
**Production effect:** none unless explicitly set; if set, it just creates a trace file the user can inspect.

## Properties enforced

- **All knobs default to OFF.** Production behavior is exactly the same with the env var unset as it would be without the code path existing at all. Asserted by `NF4_trace_disabled_by_default` and the absence of any `Sys.getenv "K4K_*"` calls in production paths beyond the explicit five enumerated here.
- **No knob bypasses a security or correctness property.** `K4K_FAULT_INJECT_ENOSPC` triggers a real rollback path that already exists for genuine ENOSPC; `K4K_TEST_TRACE_WRITES` only observes writes; the others modify only stub-or-test behavior.
- **The set is closed.** Adding a new `K4K_*` knob requires updating this file *first*. No silently-honored env vars.

## Why these are documented in the meta KB (`kb/`) rather than per-target (`.k4k/`)

These are knobs of **k4k itself**. The interaction file's user does not see or care about them. They are the responsibility of contributors maintaining k4k.

## Related files

- `spec/api-contracts.md` — the public CLI contract (which deliberately excludes these env vars)
- `properties/non-functional.md#NF4` and `#NF5` — measurement procedures relying on these knobs
- `external/claude-code.md` — how `Backend_claude` differs from `Backend_stub`
