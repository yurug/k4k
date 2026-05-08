---
audit: axis-2-security
timestamp: 2026-05-08T17:35:00Z
result: fail
---

# Findings — Axis 2 (Security)

## Per-check verdict

| # | Check                                       | Verdict          |
|---|---------------------------------------------|------------------|
| 1 | Secrets quarantine (POISON-CANARY, NF5)     | pass (with caveat) |
| 2 | Subprocess invocation (no Sys.command)      | pass             |
| 3 | State-confinement (NF4) via strace          | n/a-deferred (NF4 trace harness used as proxy → pass) |
| 4 | No untrusted-code execution paths           | **fail (high)**  |
| 5 | Logs do not leak environment                | pass             |
| 6 | `.k4k/` permissions                         | pass             |

## Critical
*(none)*

## High

- **H1 — Agent-supplied diff is applied to the working tree without path
  filtering, allowing the agent to modify `.k4k/` (k4k's own state) or
  any other repo path.**
  - evidence:
    - `lib/git.ml:99-107` — `apply_diff` runs `git apply --index <tmp>`
      with no path whitelist or rejection of `.k4k/`, `.git/`, or
      paths outside the source tree envelope.
    - `lib/diff_extract.ml:73-74` — `extract_diff` returns the raw
      diff bytes; no inspection of the affected paths.
    - `lib/gap_step.ml:152-164` — the diff returned by the agent is
      handed straight to `Git.apply_diff`; rewinds via `git reset
      --hard HEAD` only after a verifier rejection (i.e. the unsafe
      write has already happened, and the verifier can't see writes
      hidden from its focus).
    - audit-checklist Check 4 explicitly states the agent must
      "never [be allowed to write] into `.k4k/` or other repos."
  - fix: in `lib/git.ml` (or a new `Diff_filter` module called from
    `Gap_step.try_apply_and_verify`):
    1. Parse the unified diff for `+++ b/<path>` / `--- a/<path>`
       lines before invoking `git apply`.
    2. Reject (return `Error "diff touches forbidden path: <p>"`)
       if any path:
       - is `.k4k` or starts with `.k4k/`,
       - is `.git` or starts with `.git/`,
       - is absolute (`/...`),
       - contains a `..` segment,
       - is under a cotype sidecar (`.*.cotype/`).
    3. Optionally pass `--include` / `--exclude` to `git apply` as
       a defence-in-depth, but the OCaml-side reject is the
       load-bearing check (it gives a deterministic error message
       and writes a diagnostic to `.k4k/log.jsonl`).
    4. Add a unit test in `test/unit/test_unit.ml` (suite
       `NF4`/`Security`): synthetic diff that touches
       `.k4k/manifest.json` must be rejected before any FS write.

## Medium

- **M1 — `Backend_external.make_scratch_dir` falls back to
  `Filename.get_temp_dir_name ()` when `k4k_dir` is `None`, putting
  prompt files and backend output under `/tmp/k4k-backend-scratch/...`
  outside the NF4 envelope.**
  - evidence: `lib/backend_external.ml:37-45`
    (`| None -> Filename.concat (Filename.get_temp_dir_name ()) "k4k-backend-scratch"`)
  - The NF4 envelope test exercises this only with `k4k_dir = Some _`,
    so this fallback is uncovered.
  - fix: either (a) make `k4k_dir` mandatory in
    `Backend_external.config` (drop the option), or (b) raise
    `E_state_corrupt "backend scratch dir requires a k4k_dir"` when
    callers leave it unset. Production already always passes a real
    `k4k_dir`; the fallback is dead and unsafe.

- **M2 — `Toolchain_install.pkg_manager_command` writes under
  `$HOME/.local/share/k4k/npm` for npm installs, which is outside the
  NF4 envelope `<file.k4k> | <k4k_dir>/* | <workdir>/*`.**
  - evidence: `lib/toolchain_install.ml:108-111`
  - This is gated behind explicit user consent for missing binaries,
    but the audit-checklist Check 3 envelope is unconditional.
  - fix: document this exception in `kb/properties/non-functional.md
    #NF4` (allow `$HOME/.local/share/k4k/**` for explicit toolchain
    installs only); or relocate the npm prefix to `<k4k_dir>/npm`
    so installs stay in-envelope. Also handle `Sys.getenv "HOME"`
    raising `Not_found` (currently propagates as an internal
    OCaml exception rather than a typed `K4k_error`).

## Low

- **L1 — Check 1 (POISON-CANARY) automated test only triggers three
  Logger code paths, not "every error path" as
  `kb/properties/non-functional.md#NF5` and the audit-checklist
  require.**
  - evidence: `test/unit/test_unit.ml:3679-3697` —
    `nf5_secrets_canary_never_leaks` calls `Logger.info`,
    `Logger.warn`, `Logger.error` and one `Error.E_agent_unavailable`
    render. It does not exercise stdout (`Logger.stdout_line`),
    `Tty_status` updates, error paths in `verifier_external` /
    `backend_external` / `cotype` (which print sub-process stderr
    truncated to 200 bytes via `truncate_stderr` — currently NOT
    routed through `Logger.scrub`), nor the watcher's user-facing
    welcome / clarification blocks.
  - manual end-to-end check (this audit): I ran
    `ANTHROPIC_API_KEY=POISON-CANARY-XYZ123 _build/default/bin/main.exe
    ./nonexistent.k4k`; `grep -c POISON` on stderr/stdout returned
    0. The harness did not get far enough to exercise verifier or
    cotype error paths, but the agent backend error path was
    exercised and was clean.
  - fix: extend `nf5_secrets_canary_never_leaks` to
    1. set the env var,
    2. drive a full integration scenario with each of (verifier
       tool error, cotype conflict, agent timeout, agent
       budget-exhausted, manifest read failure, format error,
       verifier subprocess writing the canary on stderr, backend
       subprocess writing the canary on stderr) — a parameterised
       table of error injectors,
    3. grep stdout, stderr, and `<k4k_dir>/log.jsonl` for the
       canary; assert zero matches in all three streams.
  - additionally: route `truncate_stderr` (in
    `lib/backend_external.ml:78` and `lib/verifier_external.ml:35`)
    through `Logger.scrub` so any subprocess stderr that contains
    a leaked secret is scrubbed before it reaches the JSONL log
    or the operator's terminal.

- **L2 — `Logger.scrub` regex coverage gap: the `secret_re_kv`
  pattern requires a `:` or `=` separator after the keyword. A
  variable named `apikey_anthropic_value` followed by whitespace and
  the secret would not match. Also the regex does not catch JSON
  Web Tokens (eyJ... pattern) or sk-ant-*-style raw API keys when
  unaccompanied by a keyword.**
  - evidence: `lib/logger.ml:30-39, 42-48` — only keyword-prefixed
    or `Bearer`/`Token` style strings are scrubbed.
  - fix: add an additional pattern for high-entropy token
    silhouettes (`sk-ant-`, `sk-`, `eyJ[A-Za-z0-9_-]{20,}\.` for
    JWTs). Low priority because (a) we don't normally log raw
    tokens, (b) the keyword-based scrub catches the
    `ANTHROPIC_API_KEY=...` shape that is the actual leak risk.

- **L3 — `lib/subprocess.ml:128` defaults the child env to
  `Unix.environment ()`, i.e. inherits the full parent environment
  including `ANTHROPIC_API_KEY`. The verifier and cotype subprocesses
  do not need this. A defence-in-depth measure would be to whitelist
  `PATH`, `HOME`, `LANG`, `TZ` and explicitly drop API keys for the
  verifier (which is meant to be a hermetic property checker, never
  a network client).**
  - evidence: `lib/subprocess.ml:128`
    (`?(env = Unix.environment ())`),
    `lib/verifier_external.ml` (no env override),
    `lib/cotype.ml` (no env override).
  - fix: add `let safe_env () = ...` in `Subprocess` returning a
    minimal whitelist, and call it from `Verifier_external` and
    `Cotype`. Backend remains free to inherit the parent env (it
    legitimately needs the API key).

## Notes

### Check execution log

1. **Check 1 (POISON-CANARY)**:
   - Automated harness exists: `test/unit/test_unit.ml:3679-3697`
     (suite `NF5`). Ran `dune exec test/unit/test_unit.exe -- test
     'NF5'` → 3/3 pass. Coverage of "every error path" is partial
     (see L1).
   - Manual end-to-end:
     `ANTHROPIC_API_KEY=POISON-CANARY-XYZ123
     _build/default/bin/main.exe /tmp/poison-test/nonexistent.k4k`;
     stderr + stdout grep returned zero `POISON` matches.
   - Verdict: **pass with caveat L1**.

2. **Check 2 (`grep -r 'Sys.command' lib/`)**:
   - Command: `grep -rn 'Sys.command' lib/` → empty (exit 1).
   - Lint test `code_style_no_Sys_command` (suite `Lint`) passes.
   - Test code uses `Sys.command` (intended; see
     `test/integration/test_integration.ml`,
     `test/unit/test_unit.ml`); the audit check is `lib/`-only so
     this is OK.
   - Verdict: **pass**.

3. **Check 3 (strace state-confinement)**:
   - `strace` is not available in this sandbox (`which strace` →
     not found).
   - Best-available proxy: NF4 envelope test
     (`test/unit/test_unit.ml:3828`,
     `NF4_state_confinement_envelope`). Instruments
     `Persist.atomic_write` and `Persist.append_jsonl_line` via
     `K4K_TEST_TRACE_WRITES`. Ran `dune exec test/unit/test_unit.exe
     -- test 'NF4'` → 4/4 pass.
   - Gaps the trace doesn't see (still need a real strace run to
     audit cleanly):
     - Writes performed by the verifier subprocess (out of k4k's
       control by design).
     - Writes performed by `git apply --index` (the agent's diff
       — see H1).
     - Writes by cotype subprocess (sidecar `.*.cotype/`).
     - `Unix.openfile` calls inside `Persist` itself (the trace
       hook runs after them).
   - Verdict: **n/a-deferred**. Need: install strace, run a real
     integration scenario (`k4k <file.k4k>` with real backend,
     real verifier, real cotype), assert `^openat\|^creat\|^write`
     syscalls only target paths under `<file.k4k>`, `<workdir>/`,
     `<k4k_dir>/`, plus the documented exceptions
     (`<workdir>/.git/*`, `<workdir>/_build/*`,
     `<workdir>/.*.cotype/*`, `/dev/null`, `/dev/tty`,
     `/proc/self/*`, dynamic-loader pages under `/usr/lib`).

4. **Check 4 (untrusted-code execution paths)**:
   - The agent never executes shell from an output; its only
     side-effect channel is the unified diff.
   - However the diff is applied to the working tree
     (`git apply --index` in `<workdir>`) with no path filter, so
     it can reach `.k4k/` (k4k's own state) and any other repo
     subtree. See H1.
   - Verdict: **fail (high)**.

5. **Check 5 (logs do not leak environment)**:
   - Most recent integration log:
     `/tmp/k4k-it-333374-769754/.k4k/log.jsonl` (10593 B,
     2026-05-08 17:22).
   - Command: `grep -i "ANTHROPIC\|API_KEY\|TOKEN\|SECRET"
     /tmp/k4k-it-333374-769754/.k4k/log.jsonl` → 0 matches.
   - Spot-checked two adjacent logs
     (`k4k-it-332574-769754`, `k4k-it-331390-769754`) → 0 matches
     each.
   - Verdict: **pass**.

6. **Check 6 (`.k4k/` permissions)**:
   - Command: `find /tmp/k4k-it-333374-769754/.k4k -printf '%m\n'
     | sort -u` → `644`, `755` only. No `0o777`, no `0o600`, no
     world-writable.
   - Source: `lib/persist.ml:48` (`Unix.mkdir path 0o755`),
     `lib/persist.ml:35,65,114` (`Unix.openfile ... 0o644`).
   - Verdict: **pass**.

### Most load-bearing finding

**H1** is the single highest-risk finding. v2's "direct-commit"
gap-step (ADR-013 §2 step 3) deliberately removed the scratch-branch
isolation that v1 used, on the grounds that `git reset --hard HEAD`
on rejection is enough. But `git apply --index` happens *before* the
verifier runs, so a malicious or buggy diff can corrupt
`.k4k/manifest.json` (or any other k4k operational state file),
*and* the verifier — which only inspects properties — won't catch
it. The post-verifier rewind to `HEAD` cleans up the source-tree
half but not the `.k4k/` half (because `.k4k/` is in
`is_ignorable_path`, see `lib/git.ml:65`). Net effect: a single
poisoned diff can permanently invalidate `manifest.json`,
`version/N/audit.md`, etc., bypassing the determinism contract.

The fix (path filter on diff input before `git apply`) is small
(~30 lines), self-contained in `lib/git.ml`, and adds one unit test.
It should land before any backend other than `Backend_canned` is
unleashed against a real working tree.

### Methodology gaps

- The audit-checklist's Check 3 mandates `strace`. This sandbox
  doesn't ship `strace`; the runbook should either (a) require the
  audit be run in a container that has it, or (b) explicitly list
  the NF4 trace-hook test as the substitute and acknowledge its
  blind spots (subprocess writes, `git apply` writes, the trace
  hook's own write).
- The NF5 canary test should be parameterised over the closed
  error taxonomy (`spec/error-taxonomy.md`) so we get one test
  case per error code automatically, not a hand-rolled list of
  three.
