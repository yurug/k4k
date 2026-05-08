---
id: properties.non-functional
type: spec
summary: Measurable non-functional invariants NF1..NFN — latency, memory, durability, security envelope, audit trail.
domain: properties
last-updated: 2026-05-02
depends-on: [glossary, properties.functional]
refines: []
related: [properties.edge-cases, conventions.testing-strategy, spec.algorithms]
---

# Non-Functional Properties (NF-series)

## One-liner

Quantitative or measurable behaviors `k4k` must satisfy. Each entry has a measurement procedure so audits can verify it.

## Conventions

Each entry: **ID**, **Statement (with measurable criterion)**, **Violation**, **Measurement**, **Why**.

---

### NF1 — Signal latency
- **Statement:** From `SIGINT` or `SIGTERM` delivery to process exit, wall-clock time ≤ 5 s.
- **Violation:** k4k blocks for 30 s waiting on an HTTP timeout after Ctrl-C.
- **Measurement:** Integration test with a stubbed agent that sleeps 60 s; send SIGINT 1 s in; assert exit within 5 s of signal.
- **Why:** User control; aligns with P8.

### NF2 — Memory ceiling
- **Statement:** Resident memory < 512 MB throughout any run with `<file.k4k>` ≤ 10 MB.
- **Violation:** Loading the full agent-runs/ directory into memory blows past 1 GB.
- **Measurement:** RSS sampled every 100 ms during a fixed 50-step integration scenario; max < 512 MB.
- **Why:** k4k runs on developer laptops alongside other tools.

### NF3 — Crash atomicity
- **Statement:** A `kill -9` of k4k at any point leaves `.k4k/` in a state from which `k4k --check` can recover without `--reset`. Either: the prior step's outputs are intact, or the in-flight step is fully discarded.
- **Violation:** A truncated `manifest.json` after kill -9 mid-write.
- **Measurement:** Property-based crash test — random kill timing across 100 runs; after each, assert manifest parses and agrees with on-disk state.
- **Why:** Tied to P10. Safety under arbitrary host failure.

### NF4 — State-confinement envelope
- **Statement:** During any run, the only paths k4k mutates are `<file.k4k>`, `.k4k/<*>`, and (during gap-steps) the source tree it is building. No `/tmp`, no global state.
- **Documented exception:** When `Toolchain_install.ensure` actually performs an opt-in user-scoped install (not the `Already_present` no-op fast path), it is allowed to write under `$HOME/.local/share/k4k/<package-manager>/` for tools that require a persistent user-global prefix (notably `npm --prefix`). This path is fixed (no `$XDG_*` variation), surfaces in `.k4k/log.jsonl` as a `toolchain.install_started` event, and the user-scoped prefix is the only acceptable cross-run state we keep outside the per-project envelope. The audit's `K4K_TEST_TRACE_WRITES` hook does NOT see these subprocess writes (they're inside the package manager's process), so the strace check below is the only way to catch a violation; the exception is whitelisted by path prefix.
- **Violation:** k4k writes a cache file in `~/.cache/k4k/`, or writes ANY file outside the envelope in the `Already_present` path.
- **Measurement:** Run under `strace -e trace=openat,unlink,rename`; filter writes; assert all paths fall under the allowed set OR the documented exception prefix.
- **Why:** Reproducibility, auditability, container-friendliness.

### NF5 — Secrets quarantine
- **Statement:** Environment variables matching `(?i)(api[_-]?key|token|secret|password|bearer)` are never written to any file or any output stream. Logs scrub matching content per `conventions/error-handling.md`.
- **Violation:** A redirected stderr capture contains `ANTHROPIC_API_KEY=sk-ant-...`.
- **Measurement:** Test with poison env var `ANTHROPIC_API_KEY=POISON-CANARY`; trigger every error path; grep all output streams + `.k4k/log.jsonl` for `POISON-CANARY`; assert zero matches.
- **Why:** Trivially shipped credentials are the most common security failure in CLI tools.

### NF6 — Determinism (system-level)
- **Statement:** For fixed `(file content, .k4k/ contents, agent backend version, verifier version, k4k version, $TZ)`, two runs produce byte-identical `desired/spec.json`, byte-identical `gap/properties.json` (modulo timestamps), and the same exit code. *Not* claimed: byte-identical agent prompts (timestamps differ), byte-identical accepted patches (agent stochasticity).
- **Violation:** `k4k --check` returns different gap orderings on consecutive runs.
- **Measurement:** Snapshot test — run twice with stub agent fixed seed, diff outputs (excluding timestamps via a known list of fields).
- **Why:** Auditability, reproducibility, the whole NOTES.md thesis.

### NF7 — Audit-completeness
- **Statement:** Every state-changing event has exactly one corresponding `level: "info"` or `level: "error"` JSONL log entry. The set of artefacts named in those entries reconstructs the state of `.k4k/` at any prior point.
- **Violation:** A property transitions from `unknown` to `established` with no JSONL entry.
- **Measurement:** Replay test — take a real `log.jsonl`; rebuild a synthetic `.k4k/` from events; diff with the actual `.k4k/`; assert equal.
- **Why:** "Verifiable artefacts" per NOTES.md.

### NF8 — Pluggable-backend cost asymmetry
- **Statement:** Prompts must be designed so that the formalization and KB-regen passes succeed on the *weakest supported backend* (defined as a 7B-class local Ollama model); they must not require Claude-class reasoning. A regression that only passes on Claude is a bug.
- **Violation:** A prompt that asks for "deep architectural reasoning" and only canonicalizes correctly on Claude.
- **Measurement:** Once Ollama support ships, all prompts run on `codellama:7b` in CI; v0 places the test harness now (with `Stub_agent` configured to enforce a "weak" capability profile).
- **Why:** Architectural commitment from the user (round 2 user-added). See ADR-003 and `conventions/context-economy.md`.

## Agent notes

> **Don't mistake "tested in CI" for "satisfied."** A measurement procedure is a check; the *invariant* is what counts. If a run passes the test by coincidence (e.g. wall-clock skew), the test is broken, not the invariant.

## Related files

- `properties/functional.md` — qualitative invariants P1..PN
- `properties/edge-cases.md` — boundary conditions
- `runbooks/audit-checklist.md` — how Phase-5 audits use these
