---
audit: axis-4-ux
timestamp: 2026-05-08T18:10:00Z
result: fail
---

# Findings — Axis 4 (UX)

## Scope reminder

The v2 user surface is the watcher daemon (`k4k <file>`), the in-file
UX (clarification / status / tradeoff blocks), JSONL events on stdout,
and a tiny operator-flag set: `-v` / `-vv` / `--exit-on-stable` /
`--exit-on-done` / `--max-versions=N` (the last three documented as
test-only in `kb/runbooks/test-environment.md`). The PRD
(`kb/domain/prd.md` §"Command surface (v2)" l.94-103) makes the
contract explicit.

The audit checklist (`kb/runbooks/audit-checklist.md` §"Axis 4 — UX"
l.67-78) was authored against the v0 CLI and references a `--check`
flag that no longer exists. Where the v2 UX has *replaced* the v0
behavior, the per-check pragmatics override the checklist.

## Per-check verdict

| # | Check                                              | Verdict           |
|---|----------------------------------------------------|-------------------|
| 1 | stdout/stderr discipline (P11)                      | pass              |
| 2 | Exit codes match `spec/error-taxonomy.md`           | **fail (high)**   |
| 3 | TTY status updates correctly (single in-place line) | n/a (replaced by in-file `## k4k:status` block per v2 PRD) |
| 4 | `--check stable.k4k` prints `stable\n`              | n/a (flag removed in v2; KB sync needed) |
| 5 | Error messages cite remediation                     | **fail (medium)** |
| 6 | `-v` / `-vv` are additive                           | **fail (medium)** |

## Critical

*(none)*

## High

### H1 — Closed error catalog has unreachable IDs and the binary leaks bare runtime exceptions outside the catalog. (Check 2)

`kb/spec/error-taxonomy.md` enumerates 14 IDs.
`lib/error.ml:2-17` defines 14 `K4k_error` variants plus an unrelated
`Invariant_violation of string` exception (`lib/error.ml:20`). Three
gaps:

1. **`EOWNERSHIP_VIOLATION` (exit 64) and `EINVARIANT` (exit 64+) have
   no implementation path.** `Invariant_violation` is declared
   (`lib/error.mli:41`, `lib/error.ml:20`) but is never raised
   anywhere in `lib/` or `bin/` (`grep -rn 'Invariant_violation' lib/
   bin/` returns only the declaration). `EOWNERSHIP_VIOLATION` has
   no OCaml variant at all. The taxonomy advertises codes the binary
   cannot produce, and offers no panic-with-stack-trace path. If a
   genuine invariant violation occurred in production it would
   surface as an OCaml backtrace, exit 2, with no `please report`
   message — completely off-spec.
2. **The catalog is not exhaustive.** `bin/main.ml` invokes
   `Watcher.startup`, which calls `Persist.atomic_write` →
   `Persist.ensure_dir` (`lib/persist.ml:42-52`). `ensure_dir` only
   catches `EEXIST` and `ENOSPC`. An `EACCES` or `EPERM` from
   `Unix.mkdir` propagates as an uncaught `Unix.Unix_error`, which
   `Watcher.startup` converts to an `Aborted (Printexc.to_string …)`
   message — observed:

   ```
   $ k4k /nonexistent/path/to/missing.k4k
   k4k: Unix.Unix_error(Unix.EACCES, "mkdir", "/nonexistent")
   exit=1
   ```

   That message has no recovery hint, no error code, and is not in
   `error-taxonomy.md`. Per `error-taxonomy.md` line 132 ("Code that
   throws an exception not in this catalog is buggy") this is a
   defect.
3. **Error-code coverage in tests is patchy.** Searching `test/` for
   error-ID strings:

   | ID                     | mentions in `test/` |
   |------------------------|---------------------|
   | `EFILE_NOT_FOUND`      | 0                   |
   | `EVERSION`             | 0                   |
   | `ECLASS_UNSUPPORTED`   | 0                   |
   | `EUNSTABLE`            | 0                   |
   | `EBUDGET`              | 0                   |
   | `EVERIFIER_TOOL_ERROR` | 0                   |
   | `EDISK_FULL`           | 0                   |
   | `EOWNERSHIP_VIOLATION` | 0                   |
   | `EINVARIANT`           | 0                   |

   The variants (`E_file_not_found`, `E_disk_full`, …) are exercised
   indirectly by name, but the IDs and the exit codes the spec
   advertises are never asserted.
4. **`--help` exit-status documentation contradicts the spec.**
   `k4k --help` lists exit codes 0/123/124/125 (cmdliner defaults).
   `error-taxonomy.md` enumerates 0/1/2/3/4/5/64+. Cmdliner returns
   124 for parse errors and 125 for unexpected internal exceptions —
   neither is in the taxonomy. (Observed: `k4k --bogus-flag` →
   exit 124.)

  - **Fix:**
    - Define explicit `E_ownership_violation` and `E_internal_panic`
      variants (or a single `Invariant_violation` raise + exit-code
      mapping in `bin/main.ml`); install a top-level `Printexc`
      handler in `bin/main.ml` that converts unexpected exceptions
      into `EINVARIANT` (exit 64) with a `please report` message and
      a stack trace appended to `.k4k/log.jsonl`.
    - Wrap `Persist.ensure_dir` so `EACCES`/`EPERM`/`EROFS` map to
      `E_state_corrupt` (or a new `E_filesystem`) with a remediation
      hint.
    - Add an alcotest case per error ID checking
      `Error.code_id err = "<EXPECTED>"` and
      `Error.exit_code_of err = <expected>` (closed-set proof in
      tests, so any drift is loud).
    - Override cmdliner's exit-status block with our taxonomy via
      `Cmd.info ~exits:…`, so `--help` shows 1/2/3/4/5/64+ instead of
      123/124/125.

## Medium

### M1 — `-vv` produces zero additional output over `-v`. (Check 6)

`bin/main.ml:22-32` parses `-v` repetitions into `Quiet/Verbose/Debug`.
`Watcher.emit_event` (`lib/watcher.ml:87-99`) treats `Verbose` and
`Debug` identically: both write `[k4k] <event>\n` to stderr, and that
is the *only* stderr emission tied to verbosity. The `verbosity`
field in `Watcher_loop.config` (`lib/watcher_loop.ml:6`) is unused
inside `watcher_loop.ml` (`grep -n verbosity lib/watcher_loop.ml`
shows one match — the field declaration). `Logger.debug_line`
(`lib/logger.ml:93-96`) does honor `Debug`, but the v2 watcher path
does not call it: it constructs no `Logger.t` for engine progress.

Empirical evidence (clean fixture, fresh git repo, cotype available):

```
$ k4k -v  --exit-on-stable in.k4k 2>se1.txt   # 4 lines
$ k4k -vv --exit-on-stable in.k4k 2>se2.txt   # same 4 lines
$ diff se1.txt se2.txt   # empty
```

`-vv`'s only documented purpose ("subprocess argv listings and agent
prompt prefixes go through this channel" per
`lib/logger.ml:91-92`) is therefore unreachable from the v2 watcher.

  - **Fix:** thread the `verbosity` value through `Watcher_loop`
    (`emit_event` already receives it) so the `Debug` branch emits
    additional content — e.g. the `details` payload pretty-printed,
    or subprocess argv/exit-code lines from `lib/git.ml`,
    `lib/cotype.ml`, `lib/backend_external.ml`,
    `lib/verifier_external.ml`. Either route those modules through
    `Logger.debug_line t` (and instantiate a `Logger.t` at the
    watcher boundary), or add a `cfg.debug : string -> unit`
    callback that mirrors `cfg.emit` but only fires when
    `verbosity = `Debug`. Add a regression test asserting
    `lines(stderr -vv) > lines(stderr -v)` on the same scenario.

### M2 — Several catalog entries' user-visible messages have no remediation, and three reference flags that no longer exist in v2. (Check 5)

`lib/error.ml` rendering, cross-checked with `error-taxonomy.md`:

| Error                  | Has remediation? | Notes                          |
|------------------------|------------------|--------------------------------|
| `E_format`             | partial          | cites `line:col` (location only; no fix verb) |
| `E_unstable`           | yes              | "see clarifications appended to <file.k4k>" |
| `E_version`            | partial          | lists supported versions; no "upgrade k4k or downgrade `version`" verb |
| `E_class_unsupported`  | yes              | "(v0 supports: cli)"           |
| `E_encoding`           | yes              | "re-save the file as UTF-8"    |
| `E_file_not_found`     | yes              |                                |
| `E_file_too_large`     | yes              |                                |
| `E_budget`             | yes (BUT references `k4k.budget.hard_per_invocation` frontmatter knob) |
| `E_max_steps`          | **broken**       | "raise `--max-steps`"; flag does not exist in v2 (`bin/main.ml`) |
| `E_disk_full`          | yes              |                                |
| `E_agent_unavailable`  | **no**           | message text is just `agent backend unavailable: <details>` (`lib/error.ml:111-112`); the spec's recovery hint ("Check `$ANTHROPIC_API_KEY` / `claude` binary on `$PATH`; check network") is in the spec only |
| `E_verifier_unavailable` | **no**         | `verifier unavailable: <details>` (`lib/error.ml:113-114`); spec hint absent from message |
| `E_verifier_tool_error` | **no**          | `verifier error: <details>` (`lib/error.ml:115-116`); spec says "see .k4k/verifier-runs/<id>/" but the message embeds neither path nor ID |
| `E_state_corrupt`      | **broken**       | "consider `--reset`" (`lib/error.ml:117-118`); `--reset` flag does not exist in v2 |

Phantom-flag references actively mislead the user — they're worse
than a missing hint. Per Check 5 every `k4k:` error line must contain
"a path, a section id, or a `recovery hint`."

  - **Fix:**
    - Drop the `--max-steps` and `--reset` references; replace with
      v2-correct guidance (e.g. `E_state_corrupt` → "remove
      `.k4k/manifest.json` and re-launch k4k"; `E_max_steps` → "this
      is a test-only ceiling; raise via the test harness").
    - Embed the verifier `run_id` and `.k4k/verifier-runs/<id>/`
      path in `E_verifier_tool_error`'s rendering.
    - Add `$PATH` / `$ANTHROPIC_API_KEY` mention to
      `E_agent_unavailable` and `$PATH` mention to
      `E_verifier_unavailable`.
    - Add a unit test asserting every variant's
      `Error.render` output contains either `:` (path/line) or a
      verb from a small allow-list (`re-save`, `verify`, `split`,
      `install`, `set`, `check`, `remove`, `consider`, `raise`,
      `upgrade`, `downgrade`, `see`).

## Low

### L1 — Audit-checklist Check 4 (`--check stable.k4k`) is stale. (Check 4)

`audit-checklist.md` line 73 references `k4k --check stable.k4k`. No
such flag exists: `bin/main.ml:17-74` exposes only `FILE`, `-v`,
`--exit-on-stable`, `--exit-on-done`, `--max-versions=N`,
`--help`, `--version`. The v2 PRD `kb/domain/prd.md` line 96-99 makes
the command surface explicit: `k4k <file.k4k>` is the only public
form. The checklist is the v0 surface.

  - **Fix:** edit `kb/runbooks/audit-checklist.md` Axis-4 §Checks
    list — replace check 4 with one of:
    - "**JSONL stdout discipline (NF, P11) under `--exit-on-stable`**:
      every non-empty stdout line parses as JSON; stderr empty at
      `Quiet`."  (matches the existing
      `P11_stdout_jsonl` integration test in
      `test/integration/test_integration.ml:143-158`).
    - or fold check 4 into check 1 and renumber.
  - Cross-reference: `kb/domain/prd.md` (PRD) is the v2 authority;
    the checklist must follow.

### L2 — `bin/main.ml`'s `Cmd.info ~version:"0.2.0"` drifts from
`Manifest.k4k_version_string = "0.1.0"` (`lib/manifest.ml:4`).

  - Not a UX defect on its own, but `--version` shows `0.2.0` while
    the manifest written into `.k4k/manifest.json` says `0.1.0`. The
    user-visible mismatch will confuse anyone diffing the two.
  - **Fix:** make `Manifest.k4k_version_string` the single source of
    truth and read it in `bin/main.ml`'s `Cmd.info ~version:`.

### L3 — `append_clarification` swallows clarification-write failures.

`lib/watcher_loop.ml:34-40`:

```ocaml
let append_clarification cfg ct ~issues =
  try
    Cotype.append_clarification ct ~path:cfg.file_path
      ~questions:(questions_of_issues issues);
    cfg.emit "clarification.appended" …
  with Error.K4k_error _ -> ()
```

If cotype rejects the append (e.g. permission denied on the file),
the user sees no clarification block, no JSONL event, and the
watcher silently spins. Per `error-taxonomy.md` line 134 ("No silent
failures") this is off-policy.

  - **Fix:** emit a JSONL `clarification.write_failed` event with the
    error code/message so the operator can diagnose.

## Notes

- **JSONL discipline (Check 1) is solid.** `lib/watcher.ml:87-93`
  emits each event via `print_endline (Yojson.Safe.to_string …)` on
  stdout; user-facing errors use `output_string stderr` with the
  `k4k:` prefix. The existing
  `P11_stdout_jsonl` integration test
  (`test/integration/test_integration.ml:143-158`) asserts every
  non-empty stdout line parses as JSON and stderr is empty at
  default verbosity. Verified by re-running the binary against the
  `echo-upper.k4k` fixture.
- **Test-only flags are documented.** `--exit-on-stable`,
  `--exit-on-done`, `--max-versions=N` each carry a `Test-only:` doc
  in `bin/main.ml:33-54` and a §entry in
  `kb/runbooks/test-environment.md` l.91-123. No undocumented flags
  surface in `--help`.
- **Check-3 (TTY single-line) is genuinely n/a in v2.** `Tty_status`
  exists (`lib/tty_status.ml`) and is invoked from `lib/run_loop.ml`,
  but `Run_loop` itself is orphan — no other module imports it
  (`grep -rn 'Run_loop' lib/ bin/` returns only its own files and
  one logger comment). The v2 PRD declares the in-file `## k4k:status`
  block the only display surface (`kb/domain/prd.md` line 122). The
  watcher's only stdout output is JSONL events — exactly what `tee`
  consumers want, one line per transition.

## Most user-facing finding

**M2** — phantom-flag remediation in error messages (`E_state_corrupt`
suggests `--reset`, `E_max_steps` suggests `--max-steps`; neither
flag exists in the v2 binary). A user who sees the message is being
told to run a flag the binary will reject. This is the kind of bug
that erodes trust in error messages immediately.
