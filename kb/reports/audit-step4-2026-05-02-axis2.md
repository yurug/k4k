---
audit: axis-2-security
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 2 (Security)

## Method

1. NF5 secrets-canary test (unit): `NF5_secrets_canary_never_leaks`
   exercises the JSONL path with a poison-canary env var; assertion
   passes. The expanded `Logger.scrub` regex covers `KEY=VALUE`,
   `key: value`, and `Bearer <token>` shapes.
2. `grep -r "Sys.command" lib/` returns empty. The convention is
   enforced by the `code_style_no_Sys_command` lint test.
3. State-confinement: every write in `lib/persist.ml` is parameterised
   by an explicit path; the `bin/main.ml` entry point only writes to
   `.k4k/` and the working directory.
4. Untrusted code path: agent-written code is applied on a scratch
   `git` branch via `Gap_branch.create`; `gap-step.start` /
   `gap-step.accept` events log every transition.
5. Logs do not leak environment: confirmed by `NF5_secrets_canary_*`
   plus the additional `NF5_scrub_handles_token_keyword` and
   `NF5_scrub_handles_password` tests.
6. Permissions on `.k4k/`: `Persist.ensure_dir` uses `0o755` for
   directories and the kernel default `0o644` for files via
   `Unix.openfile ... 0o644` in `with_out_fd` and `append_jsonl_line`.
   A `0o777` byte literal does not appear anywhere in `lib/`.

## Critical
(none)

## High
(none)

## Medium
- The fault-injection hook `K4K_FAULT_INJECT_ENOSPC` is a debug surface;
  documented in the `.mli` and only active when the env var is set.
  Recommend adding a unit-level reminder that production deployments
  ought to filter this env (operational note, not a code change).

## Low

## Notes

Audit checks Pass status mapped to runbook Axis-2 checks 1-6 (all pass):

| Check | Status |
|-------|--------|
| 1. Secrets quarantine canary | PASS |
| 2. No `Sys.command`           | PASS (lint) |
| 3. State-confinement (writes) | PASS (per-call paths only) |
| 4. Untrusted code via git branch | PASS |
| 5. Logs do not leak env       | PASS (NF5 canary) |
| 6. `.k4k/` permissions        | PASS (0o755 / 0o644 only) |
