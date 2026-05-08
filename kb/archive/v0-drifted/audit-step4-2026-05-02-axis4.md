---
audit: axis-4-ux
timestamp: 2026-05-02
result: pass
---

# Findings — Axis 4 (UX)

## Method

1. Stdout/stderr discipline (P11): `P11_stdout_pipeable` (integration
   test) confirms that stdout has exactly one line, stderr is empty
   at default verbosity.
2. Exit codes: every error in `spec/error-taxonomy.md` is mapped to
   an exit code in `Error.exit_code_of`; covered by `P7_exit_codes_in_range`.
3. TTY status: Step-4 introduces `Tty_status` with auto-disable on
   `!isatty(stdout)`. The unit tests
   `Tty_status_render_includes_property_id` and
   `Tty_status_render_eta_dashes_when_empty` exercise the rendering;
   integration of the in-place line into `Run_loop` is gated by
   `Tty_status.is_tty ()` so piped invocations are unaffected
   (P11 preserved).
4. `--check` is silent on success: `S5_check_subcommand_exits_0_when_stable_structural`
   checks `stdout = "stable\n"` and `stderr = ""`.
5. Error messages cite remediation: every `Error.render_*` function
   includes a path, section id, or recovery hint (e.g. "consider
   --reset", "rolled back").
6. `--help` exists via `Cmdliner` and matches `domain/prd.md#command-surface`.

## Critical
(none)

## High
(none)

## Medium
- The TTY status line printed by `Tty_status.print_inplace` is opt-in
  via `is_tty ()`; tests validate the renderer but the side-effect
  `Run_loop` integration is intentionally minimal in v0 to preserve
  P11. A future iteration may wire it more deeply.

## Low
- The `--help` doc string mentions "k4k — KISS for KISS, deterministic
  harness." which does not include the full PRD command-surface
  description; readability is acceptable.

## Notes

Audit verified that:
- piping stdout still produces `done\n` / `stable\n` and not the
  in-place line (auto-disable);
- error paths route via `Logger.error` and emit `k4k: <msg>` on
  stderr regardless of verbosity.
