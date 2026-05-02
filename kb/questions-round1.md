---
phase: 1
round: 1
created: 2026-05-02
status: awaiting-user
---

# k4k — Round 1 Ambiguity Resolution

> **How to use this file**
> Each question has a *Default* I (Claude) propose based on `kb/NOTES.md`. To accept, leave it as-is. To override, replace the *Default* line with your answer (keep the `Default:` prefix or change to `Answer:` — both work). To flag as still open, write `Default: TBD`. Add new questions at the bottom under *§ User-added*. When you're done editing, tell me to proceed.
>
> Goal: eliminate every blind spot before we touch the KB. This is the cheapest round of the project — every assumption I make here that turns out wrong becomes architectural rework later.

---

## § Meta / Project framing

Before anything else, a sanity check on what we're building and why. `k4k` is itself a coding agent — we are using a coding agent (Claude Code, following the agentic-dev-kit methodology) to build another coding agent (`k4k`, following its own characterization-driven methodology). I want to confirm the recursion is intentional.

**1. What is the deliverable for v0 (the first ship-able cut)?**
Default: A POSIX CLI named `k4k` that (a) parses an interaction file, (b) detects whether it is "stable", (c) maintains a `.k4k/` knowledge base on disk, (d) calls one external coding agent in headless mode to make progress, (e) calls one verifier to evaluate the gap, (f) prints a one-line status with ETA. End-to-end on one toy example, not a finished product.

**2. Is `k4k` itself meant to satisfy its own KISS / POSIX-like definition (i.e. dogfooding)?**
Default: Yes. `k4k`'s observable behavior must be fully determined by CLI args + filesystem contents, no hidden network state beyond explicit calls to coding-agent APIs and verifier binaries (those are I/O like any other).

**3. Who is the v0 user?**
Default: A single developer on Linux/macOS, comfortable with a shell, who already has API credentials for at least one coding agent and one verifier installed. No team / multi-user / SaaS mode.

**4. Is the methodology itself (characterization-driven, harness-based) a v0 feature, or just an ambient design philosophy?**
Default: v0 ships the *workflow* (D → S → P → modify → loop), but the *generality* (multi-verifier, custom DSL building) is deferred. v0 hardcodes a small set of verifiers and one agent backend.

---

## § Implementation language & runtime

**5. What language is `k4k` implemented in?**
Default: OCaml. Reason: the verifier ecosystem cited in NOTES.md (Rocq, Frama-C) is OCaml-native, the user's affiliation (Nomadic Labs) is OCaml-heavy, and OCaml gives us a strong type system for the harness data model. Alternatives I considered: Rust (great tooling but heavier), Python (faster to prototype but weaker invariants), Go (fine but no natural fit with verifier ecosystem).

**6. Build system?**
Default: `dune` + `opam`. Lockfile via `opam.lock` for reproducibility.

**7. Minimum supported OCaml version?**
Default: 5.1+ (effects + domains may matter for concurrent agent calls; if not, we can downgrade to 4.14 LTS).

**8. Target platforms for v0?**
Default: Linux x86_64 + macOS (Intel and ARM). Windows out of scope.

**9. Distribution?**
Default: source via opam pin during v0; no binary releases yet.

---

## § Interaction file (the user's input to `k4k`)

The interaction file is the single most novel concept in NOTES.md. Many of the design choices here lock in the rest of the system.

**10. File extension and naming convention?**
Default: `*.k4k`. The CLI invocation is `k4k myproject.k4k`.

**11. Underlying syntax?**
Default: Markdown with YAML frontmatter. Rationale: humans already know it, agents already produce it, and we get section structure for free via headings.

**12. How are user-owned and k4k-owned sections distinguished?**
Default: HTML-style fenced regions with explicit ownership tags:
```
<!-- k4k:owner=user begin -->
... user content ...
<!-- k4k:owner=user end -->
<!-- k4k:owner=k4k begin id=gap-analysis-2026-05-02 -->
... agent content ...
<!-- k4k:owner=k4k end -->
```
The CLI refuses to write inside `owner=user` regions, ever. It refuses to read `owner=k4k` regions as authoritative if the human hand-edited them (detected via a hash in the begin tag).

**13. What does "stable" mean concretely?**
A file is stable if every required user-owned section is present AND non-empty AND parses without ambiguity per our schema (which we'll define in `kb/spec/data-model.md`) AND (important) does not contain any ambiguities about the program to build (i.e. a formal specification can be written) AND (important) covers enough aspects to correctly capture the user intent

Otherwise unstable, and `k4k` blocks with a precise message naming the missing/ambiguous section.

**14. Required user-owned sections?**
Default (minimum viable):
- `## Goal` — one paragraph, prose
- `## Inputs and outputs` — for each: name, type, allowed values, examples
- `## Acceptance examples` — at least 3 input/output pairs the program must satisfy
- `## Out of scope` — what the program must NOT do
- `## Verifier preferences` (optional) — which verifier(s) to use; otherwise k4k picks

**15. Concurrent edits: the user may edit the file while k4k is running. What's the contract?**
Default: k4k takes a `flock(2)` advisory lock on the file for the duration of any write. On read, it re-reads from disk before each step (no in-memory cache). If the user edits during a long-running step, k4k finishes that step, then re-reads and re-evaluates the gap.

**16. What if the user hand-edits a `k4k:owner=k4k` section?**
Default: k4k detects the hash mismatch, prints a warning, and treats that section as user input (i.e. the user has effectively claimed it). k4k will not overwrite without `--force-reclaim`.

---

## § Knowledge base on disk (`.k4k/`)

NOTES.md says k4k "maintains a knowledge base in the file system". This needs concrete structure.

**17. Layout of `.k4k/`?**
```
.k4k/
  <file hierarchy of a knowledge base as described in the agentic-dev-kit>
  # and also for the specificities of k4k:
  characterization/
    desired/         # extracted from interaction file (D)
    current/         # extracted from source + verifier output (S)
  gap/
    properties.json  # P = D \ S, with risk ranking
  agent-runs/
    YYYY-MM-DD-HH-MM-SS-<id>/
      prompt.md
      response.md
      diff.patch
      verdict.json
  verifier-runs/
    YYYY-MM-DD-HH-MM-SS-<id>/
      stdout.log
      stderr.log
      result.json
  manifest.json      # current state, hashes, ETA model
```

Look at the agentic-dev-kit methodology to maintain a useful knowledge
base. 


**18. Is `.k4k/` versioned in git?**
Default: No by default — we ship a `.gitignore` snippet. The user can opt in for audit purposes.

**19. Garbage collection of old runs?**
Default: keep last 50 agent-runs and last 50 verifier-runs; older ones moved to `.k4k/archive.tar.zst`. Configurable via `[k4k.retention]` in interaction file frontmatter.

---

## § The harness algorithm

**20. How is "the gap" represented internally?**
Default: A set of named properties. Each property has `{id, statement, status: ∈ {required, established, contradicted, unknown}, evidence: list-of-artefact-refs, risk-score: 0..1}`. The gap is the subset where `status ≠ established`.

**21. How does k4k pick the next property P to tackle?**
Default: Argmax `risk-score`. Risk score = `severity * uncertainty * blast-radius`, all in [0, 1], computed by a deterministic scoring function defined in `kb/spec/algorithms.md`. No agent judgment in the ranking.

**22. What does "modify software to get P + S" mean concretely in the loop?**
Default: k4k drafts a coding-agent prompt that names P and the current S, sends it to the agent backend in headless mode, receives a patch, applies it on a scratch branch, runs the verifier, and accepts iff the verifier says P is now established AND no previously-established property regressed.

**23. What if the verifier rejects?**
Default: roll back the patch, log the verdict, increment a per-property failure counter. If a property fails 3 times, k4k marks it `blocked` and asks the user (via an `owner=user` section appended to the interaction file) for guidance.

**24. Convergence guarantee?**
Default: None at the level of "this will always finish". We promise *monotonic non-regression* (no established property ever becomes un-established without the user changing D) and *termination on user signal* (Ctrl-C is honored within ≤5 s).

---

## § Coding-agent backend (the thing k4k calls headless)

**25. Which agents does v0 support?**
Default: Exactly one — Claude Code in headless mode (`claude -p` / SDK), invoked via subprocess. Adding more is a v1 task.

**26. How does k4k authenticate?**
Default: It does not. It inherits the user's environment (e.g. `ANTHROPIC_API_KEY` or whatever the agent's CLI expects). k4k never reads or writes credentials.

**27. How is non-determinism of the agent reconciled with determinism of the harness?**
Default: The *harness* is deterministic — for the same (D, S), it always asks the same question and applies the same scoring to the response. The *agent* is stochastic — its patches differ run-to-run. That's fine: k4k accepts only patches the verifier validates. Run-to-run differences in *which* patch lands are acceptable; differences in *whether* the property gets established are not (and must be addressed by improving the prompt in `kb/spec/algorithms.md`, not by retrying with hope).

**28. Per-agent-call budget?**
Default: Soft cap of 100 tokens-equivalent budget units per gap-step (configurable). Hard cap of 1000 per `k4k` invocation. Exceeding triggers the same blocked behavior as a verifier rejection.

---

## § Verifiers

**29. Which verifiers does v0 support?**
Default: Exactly one — a typecheck + test-suite verifier for OCaml programs. (Yes, k4k v0 only writes OCaml programs.) Real Rocq/Frama-C/Verus integration is v1+. This is deliberately narrow to ship a working harness end-to-end.

**30. How does k4k discover the verifier?**
Default: `which dune` on `$PATH`. If absent, k4k errors out at startup with a remediation message.

**31. Verifier output → property status?**
Default: A small adapter module `Verifier.Ocaml_dune` parses dune output. Test names follow a convention `P<n>_*` so the adapter can map test → property. Convention enforced by k4k when generating tests.

**32. Self-built DSL / verifier (mentioned in NOTES.md)?**
Default: Out of scope for v0. We document the extension point in `kb/architecture/decisions/adr-NNN-verifier-extension.md`.

---

## § CLI / UX

**33. Exact command surface for v0?**
Default:
- `k4k <file.k4k>` — run one full convergence pass
- `k4k --check <file.k4k>` — only verify stability, no agent calls
- `k4k --status <file.k4k>` — print current gap, no work
- `k4k --reset <file.k4k>` — wipe `.k4k/` (with `--yes` to skip prompt)
- Flags: `-v` / `-vv` (verbosity), `--no-color`, `--max-steps N`

**34. Default output (TTY)?**
Default: One line, in-place updated: `[k4k] step 3/? • property P7 (parser-handles-empty) • agent ████░░░░ • ETA 2m`. Auto-disable in-place updates when `!isatty(stdout)`; in that case, one log line per state transition.

**35. ETA model?**
Default: Sliding median of the last 10 gap-step durations × current gap size. Documented as best-effort; never blocks anything.

**36. Exit codes?**
Default: `0` success (gap empty), `1` user error (file unparseable, file unstable, etc.), `2` verifier failure on initial read, `3` agent backend unavailable, `64+` reserved.

**37. Logging?**
Default: Plain text to stderr at `-v`; structured JSON-lines to `.k4k/log.jsonl` always.

---

## § Security & safety

**38. Sandboxing of agent-written code?**
Default: v0 runs everything in the user's working directory with the user's privileges. We document the risk in `kb/runbooks/security.md` and recommend running in a container or VM. Hardening is v1.

**39. Network access during agent calls?**
Default: Yes (required to reach the agent backend). No outbound traffic from k4k itself beyond that.

**40. Secrets handling?**
Default: k4k never logs environment variables. Subprocess invocations use `execve` directly, never via `system(3)`. Logs scrub anything matching `(?i)(api[_-]?key|token|secret)\s*[:=]\s*\S+`.

---

## § Edge cases (T-entries we'll codify in `kb/properties/edge-cases.md`)

**41. Empty interaction file?**
Default: `unstable`, exit 1, message naming missing required sections.

**42. Interaction file with conflicting acceptance examples?**
Default: `unstable`, exit 1, message naming the conflicting examples by line number.

**43. Working directory contains a pre-existing program that already partially satisfies D?**
Default: Supported — the first verifier run discovers the established subset; gap = D \ established.

**44. User edits the file mid-run?**
Default: see Q15.

**45. Disk full during agent or verifier run?**
Default: rollback, exit ≥4, message naming the path that ran out.

**46. Unicode / non-ASCII in interaction file?**
Default: UTF-8 only, validated at parse time. BOM stripped.

**47. Interaction file > 10 MB?**
Default: Reject with `unstable` + message; the design assumes specs are small.

---

## § Out of scope for v0 (please confirm exclusions)

Default exclusions — call out anything you want IN scope:
- GUI / TUI dashboard
- Multi-user / team mode
- Cloud / SaaS deployment
- Plugins for additional agent backends beyond Claude
- Plugins for Rocq / Lean / Verus / Frama-C / AFL
- Custom DSL compilation
- Distributed / parallel gap-step execution
- Self-hosted model inference
- IDE integration

---

## § User-added

(Add your own questions or override defaults in this section.)
