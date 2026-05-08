---
phase: 1-redux
round: 4
created: 2026-05-08
status: awaiting-user
follows: kb/archive/v0-drifted/questions-round{1,2,3}.md
---

# k4k v2 — Round 4 Ambiguity Resolution

> **Why a round 4?**
> The v0/v1 build (213 tests, ADRs 003–010, retrofits) shipped a *developer-CLI tool* — wrong product. Your feedback (`kb/archive/v0-drifted/feedback-from-user-2026-05-08.md`) reframes k4k as an autonomous coding agent: the user only writes prose in a `.k4k` file via cotype; k4k watches, asks clarifying questions in-line, then develops + verifies in **full autonomy** with **full formal verification by default**. The v0 KB is archived; the active KB has been rewritten against the v2 vision (one commit, `f47ebbb`).
>
> What's already settled (do not re-ask):
> - cotype handles concurrency on the `.k4k` file (ADR-010).
> - Verifiers and backends are external executables conforming to wire protocols (ADR-008/009).
> - Canonical AST + two-run formalization (ADR-005).
> - Two-layer KB: `kb/` for k4k itself, `.k4k/` for the program k4k builds (ADR-006).
> - Deterministic in-process kb-regen for v0; agent-driven path wired but inactive (ADR-007).
> - The verification baseline is **Tier A** (Rocq+Extraction, Frama-C, Lean, Verus, F*); **Tiers B and C require user sign-off in-file**.
>
> What this round pins down: the *operational details* of the autonomous-agent UX. Edit each *Default* in place; replace with `Answer:` if overriding; write `TBD` for anything still genuinely open. Add new questions under *§ User-added*. Tell me when done.

---

## § A. Watcher process model

Decisions about how `k4k` runs as a long-living process.

**A1. `k4k <file>` — daemon, foreground process, or service?**
Default: **Foreground process**. The user runs `k4k myproject.k4k` in a terminal (or wraps it in their own `nohup`/`tmux`/`systemd --user` if they want it backgrounded — that's their prerogative, not k4k's concern). Ctrl-C exits the watcher gracefully (`SIGTERM` same). No daemonization built in.

**A2. What does the foreground process *show*?**
Default: structured JSONL on stdout (one line per state transition; mirror of `.k4k/log.jsonl`). At default verbosity, stderr is empty. Operators piping into `jq`/log aggregators consume stdout. End users read the `.k4k` file — they don't watch the terminal.

**A3. Multiple invocations on the same file?**
Default: **The second invocation refuses and exits 5 with a stderr message naming the running PID.** Detection via a PID file at `.k4k/watcher.pid` written on startup, removed on graceful exit. Stale PID files (process gone) are reclaimed. Rationale: avoids two watchers writing through cotype concurrently with different in-flight versions; the right way to "share" the file across machines is git, not concurrent watchers.

**A4. Watcher crash recovery?**
Default: state is fully persisted in `.k4k/` per ADR-006/007. On crash mid-development, the next `k4k <file>` invocation reads `manifest.json`, checks for an in-flight version (a `## k4k:version:<n>` block in the file with `state: developing`), and resumes from the last completed gap-step. No lost work for accepted patches; in-flight unaccepted patches are discarded (consistent with P5 non-regression).

**A5. Polling vs event-driven file watching?**
Default: **`cotype status` polled at 2 Hz** (every 500 ms). Simple, portable, deterministic. inotify/FSEvents would be faster but add platform complexity and are not needed at human-edit timescales. The poll loop also handles SIGINT/SIGTERM checking.

---

## § B. First-run UX and minimal-spec handling

The user has just installed k4k and runs it on a file containing only their prose.

**B1. User runs `k4k myproject.k4k` on a *file that doesn't exist* — what happens?**
Default: **k4k creates the file with a starter template** (frontmatter + Markdown headings outlining the required user-owned sections for `class: cli`) and immediately enters watch mode. The starter template includes a top `## How to use this file` section explaining the protocol (write your spec; k4k will append clarifications; reply in place; cotype handles concurrency; never edit `## k4k:*` machine-managed blocks).

**B2. User has typed only prose — *no YAML frontmatter* — what happens?**
Default: **k4k auto-inserts the minimal frontmatter** (`k4k.version: 1`, `class: cli`) on its first cotype save and proceeds. The user never has to write YAML. If k4k cannot infer the class (e.g. the prose suggests a library, GUI, daemon — none of which v2 supports), it appends a clarification block: "I can only build CLIs in v2; this looks like X. Want me to treat it as a CLI, or wait for v3+?"

**B3. Spec is unstable on first read — does k4k append clarifications immediately, or wait?**
Default: **wait briefly (~5 s of editor inactivity), then append**. The user is probably still typing. Detection: `cotype status` returns `clean` and the file's mtime hasn't changed for 5 s. Avoids the annoying "k4k spammed me with questions while I was mid-sentence" failure mode.

**B4. Does k4k introduce itself in the file?**
Default: **Yes, on first run only.** The starter template (B1) and a one-time `## k4k:welcome` section (auto-deleted by k4k after the user has answered the first round of clarifications) explain what k4k will do. Removable by the user any time.

**B5. Existing v0-shaped `.k4k` files (with HTML ownership tags, `k4k.backend.command` frontmatter, etc.)?**
Default: We never used this v0. 

---

## § C. In-file control surface (k4k-managed section conventions)

Pinning the exact format of the four section types `spec/config-and-formats.md` enumerates.

**C1. `## k4k:status` — what fields?**
Default:
```markdown
## k4k:status

**State:** developing version 2
**ETA:** ~12 minutes
**Tier distribution:** 10/12 properties at Tier A · 2/12 at Tier B (signed-off in tradeoff:proposal:2026-05-08-1135)
**Pending user edits:** 1 section changed; will queue for version 3
**Last activity:** 2026-05-08T11:47:32Z — `Verifier_external` accepted `P_argv_handles_upper`

(Read this section. Do not edit it. To request a rollback, see "User
control directives" below.)

### User control directives
(empty unless you want to issue one)
- `request: rollback` — abort the current version; revert to previous
- `request: pause` — pause development (k4k stops the gap-step loop until you remove this directive or save the file)
```
The block is fully replaced by k4k each update (~every 30 s during development; on every state transition; on every save).

**C2. `## k4k:version:<n>` — what fields?**
Default:
```markdown
## k4k:version:1

- **Hash:** `D-sha256:abc...123`
- **Stabilized:** 2026-05-08T10:42:11Z
- **Property count:** 12
- **Verification tier per property:** see `.k4k/version/1/tiers.json`
- **State:** done · 12/12 verified · 10 Tier A, 2 Tier B
- **Implementation:** `src/echo/` (extracted from `proofs/echo.v`)
- **Audit artefact root:** `.k4k/version/1/`
```
Versions accumulate in the file as the user iterates; k4k does not delete old version blocks.

**C3. `## k4k:clarification:<ts>` — same shape as v0?**
Default: yes, with one tweak — each block is *self-contained* (no cross-references between blocks). One block per "round" of questions, dated. Format:
```markdown
## k4k:clarification:2026-05-08-094200

I cannot proceed because:

1. Your "## Acceptance examples" section says `echo hi → "hi\n"` but
   "## Refusing examples" says `echo hi → error EBADARG`. These
   contradict.

2. Your "## File-system contract" is missing. For a class:cli program
   I need to know: does the program read or write any files? If not,
   write "N/A" with rationale.

Reply by editing the relevant user-owned section directly. Save when
done; cotype merges your answer with my next pass.
```

**C4. `## k4k:tradeoff:proposal:<ts>` — exact format and approval syntax?**
Default:
```markdown
## k4k:tradeoff:proposal:2026-05-08-110500

**Property:** `P_terminates_on_well_founded_input`
**Tier-A attempt:** failed after 4 minutes / 8000 budget units. Specifically,
the Rocq proof requires an induction on a measure I cannot synthesize
automatically given the current spec.

**Proposed:** drop this property to **Tier B** — formalize the termination
predicate as a Rocq specification, hand-write the OCaml implementation,
and verify conformance against 10 000 randomized inputs + a 1-hour
fuzzing campaign.

**What's lost:** a proof of universal termination on all well-founded
inputs. What's gained: confidence on the tested distribution.

**Approval:** to approve, replace this section's last line with:
`Approved: Tier B`
To reject (and have me retry Tier A with more budget or a decomposition
hint), write:
`Rejected: <your guidance>`
I will wait for your edit.

Approval:
```

**C5. Signing off — does k4k re-parse the section to detect the user's reply?**
Default: yes, on every cotype `save` event. The polling loop in A5 picks up the user's answer within ~500 ms.

---

## § D. Version lifecycle

The state machine for a version once stability is achieved.

**D1. Version states.**
Default: `Drafting → Refining → Stable → Developing → Awaiting-Tradeoff-Sign-Off → Developing → Done`. Plus side states: `Paused-Unknown-Unknown` (k4k discovered an issue mid-dev; back to Refining for next version), `Rolled-Back` (user requested abort).

**D2. User edits a user-owned section while a version is `Developing` — what happens?**
Default: **the edit is recorded as "pending for version N+1"**, surfaced in the status block ("1 section changed; will queue for version 3"), but does *not* interrupt version N. Version N continues to completion against its frozen `D`. When N completes, k4k re-runs stability against the user's accumulated edits → version N+1.

**D3. User edits *during* the small windows between versions (after N done, before N+1 stability check)?**
Default: ordinary user edits — k4k re-runs stability per usual. No special handling.

**D4. Rollback during in-flight development.**
Default: user adds `request: rollback` to the `## k4k:status` block's "User control directives" subsection. k4k detects on next poll, aborts version N's gap-step loop, reverts the source tree to the state at version N-1's completion (or to the empty pre-v0 state if there's no prior version), updates the version block to `state: rolled-back`, archives `.k4k/version/<n>/` for forensics, and re-enters `Refining` against the user's current spec (which becomes the spec for version N+1, taking the `request: rollback` directive as a one-time signal).

**D5. Pause vs rollback.**
Default: `request: pause` halts the gap-step loop (k4k stops issuing agent calls and runs no verifier) but does NOT revert source. The version stays in `Developing` state with a `paused: true` flag in the status block. To resume, the user removes the directive and saves. Useful for "I want to inspect what k4k has built so far before it does more."

**D6. Done with leftover unfinished properties (e.g. user signed off a Tier-C drop).**
Default: a version is `Done` only when the gap is empty *under the current per-property tier assignments*. If 10 are Tier A and 2 are Tier C (signed off), and all 12 verify under their assigned tiers, the version is Done. The `## k4k:version:<n>` block records the tier mix prominently.

---

## § E. Tier-A toolchain set and self-selection

**E1. Which Tier-A toolchains does v2 commit to shipping support
for?**  

The underlying model (Claude, GPT...) will know how to use the
toolchains: there should be no need for adhoc support for them in
k4k. Don't focus on my examples (Rocq, frama-C): they are just
examples. For each project, k4k should ask itself what is the best
toolchains to use and adapts.

**E2. How does k4k choose between Rocq-extraction and Frama-C for a given spec?**
See previous question's answer.

**E3. What about the agent backend? Same self-selection?**
Default: yes. k4k probes the host: if `claude` is on PATH and authenticated → use it. Otherwise check `OLLAMA_HOST` and Ollama availability → use it. Otherwise surface a clarification block: "I need access to a coding agent. Options: install Claude Code (`pipx install claude` and authenticate), or run a local Ollama (`ollama pull qwen3.5:9b`). Tell me which."

At some point, k4k will use multiple models depending on the complexity of the task. For instance, it is complex to set up a Coq proof top-down (the right main theorem and definitions, the right proof structure etc) so this should be given to a frontier model. By contrast, it is perfectly possible that smaller models are sufficient to prove the technical lemmas (just to write the proof scripts). Again, that's just an example but you should prepare for this because we want to optimize for token consumptions at some point.

**E4. Self-installation of missing tools — do or don't?**
Default: **don't auto-install**. Prompt the user via a clarification block. Auto-installing system packages (opam, apt, pip) without consent is overreach. k4k can however check for *opam-managed* tools and offer "I can `opam install coq frama-c` for you; reply `Approved: install` to proceed." Same shape as a tradeoff proposal — explicit user consent in the file.

**E5. Tool-version requirements.**
The user does not want to do that. k4k needs to install what's useful.

**E6. Per-property toolchain assignment within a single version?**
Default: **same toolchain per version** for v2 simplicity. If the spec mixes (e.g. 80% pure-functional, 20% pointer-heavy), v2 surfaces this as a structural decomposition the user must accept (split the .k4k into two specs, one per language). v3+ may relax. Rationale: cross-toolchain composition (Rocq proving pre/post for a Frama-C-verified C library, say) is research-grade; v2 stays narrow.

---

## § F. Tier-A failure detection, negotiation, and decomposition

**F1. How does k4k decide Tier-A is "too hard" for a property?**
Default: **time + budget bound**. The agent has at most N attempts (default 5) at proving the theorem; each attempt has a per-call budget cap; cumulative wall-clock cap is ~2× the median proof-time on already-completed Tier-A properties for the same version. If the bound is hit, k4k opens a tradeoff proposal. (k4k does NOT pre-judge "this property is hard" — it tries first.)

**F2. Decomposition: does k4k attempt to break large theorems into lemmas autonomously?**
Default: **yes, OF COURSE, as part of its Tier-A attempts**. Specifically, the gap-step prompt for Tier-A includes "if the theorem is too large to prove directly, propose a decomposition into smaller lemmas; emit them as additional properties for k4k to verify." If decomposition fails (the agent can't find a useful split), the property goes through the tradeoff-proposal flow.

**F3. User-supplied decomposition hints.**
Default: **opt-in, not required**. The user CAN write a section like `## Decomposition hints` that names lemmas they think the agent should prove (e.g. "First prove `terminates_when_input_well_founded` for `well_founded` defined as the lexicographic order over `(input_length, --upper_flag)`."). If present, k4k uses them. If absent, k4k attempts decomposition autonomously.

**F4. Per-property tier tracking — granularity in the status block.**
Default: aggregate counts in the status block ("10/12 Tier A · 2/12 Tier B"); per-property detail in `.k4k/version/<n>/tiers.json` and the version block points to it. The user can read `.k4k/...` if they want detail; the status block stays human-scannable.

**F5. Tradeoff approval — what does the user actually write?**
Default: `Approved: Tier B` (or `Approved: Tier C`) replacing the empty `Approval:` line in the proposal block. k4k re-reads on next poll, transitions the property to the approved tier, and continues.

**F6. Tradeoff *rejection* with guidance.**
Default: `Rejected: <free-form text>` — user supplies guidance for k4k's next Tier-A attempt (e.g. "Try a different proof strategy: induction on argv length"). k4k incorporates the guidance into its retry prompt; budget is reset for one more attempt. If that also fails, k4k opens a *new* tradeoff proposal (one timestamp later) acknowledging the rejected guidance.

**F7. Multiple simultaneous tradeoff proposals?**
Default: **no — one open proposal at a time**. If a second property hits Tier-A bound while the first proposal is still awaiting the user, the second waits in a queue (k4k notes it in the status block: "2 properties pending tradeoff; awaiting your reply on first proposal"). Avoids overwhelming the user with parallel decisions.

---

## § G. Persistence, audit, and verifiable artefacts

**G1. `.k4k/version/<n>/` directory layout.**
Default:
```
.k4k/version/<n>/
  D-spec.json           # canonical AST, immutable post-stability
  tiers.json            # per-property tier assignments + sign-off references
  proofs/               # for Tier-A Rocq: *.v files + extraction config
  c-sources/            # for Tier-A Frama-C: *.c + *.h with ACSL annotations
  src/                  # extracted/verified implementation source
  manifest.json         # this version's manifest (tool versions, hashes)
  audit.md              # human-readable summary of every accepted property
                        # and its verification artefact
```

**G2. What does the audit report contain (per version)?**
Default: a Markdown file mapping each property ID to: (a) the theorem/contract that establishes it, (b) the file/line where the proof closes, (c) the verifier output excerpt, (d) the tier (A/B/C) plus sign-off pointer. Reproducible: `coqc proofs/*.v` (or `frama-c -wp ...`) re-checks every claimed theorem.

**G3. Are old versions kept in `.k4k/` indefinitely?**
Default: **yes, all versions are kept by default**. Disk space is cheap; an old version is documentation. The user can opt into rotation via a `kb/runbooks/`-documented manual cleanup if needed; k4k itself never deletes.

---

## § H. Observability for operators (not part of the user UX)

**H1. `-v` / `-vv` semantics.**
Default: `-v` adds engine-level transitions to stderr (every gap-step start/accept/reject; every cotype save outcome). `-vv` adds subprocess argv (verifier + backend invocations, with prompts truncated to 200 chars). At default verbosity (no flags), stderr is empty.

**H2. Operator's view of the in-file events?**
Default: stdout JSONL is the canonical operator stream. It includes everything the user sees via `## k4k:status` PLUS engine-level transitions invisible to the user (gap-step decisions, agent calls, verifier exit codes).

---

## § I. Cross-cutting

**I1. Backwards-compat with the v0 demo.**
Default: the `tests/fixtures/echo-upper.k4k` fixture is rewritten to v2 format (no tooling frontmatter, no HTML ownership tags). The v0 form is preserved at `kb/archive/v0-drifted/echo-upper-v0.k4k` for reference. Integration tests that exercised v0 flags are deleted (the wrapper rewrite removes the underlying code).

**I2. The Tier-C example (`examples/verifiers/dune-ocaml/`) — keep, archive, or delete?**
Default: **delete**

**I3. `examples/backends/{claude-code, ollama}/` — still valid?**
Default: yes. The backend protocol is unchanged from v1. Both reference backends are appropriate for v2 (claude-code is a strong Tier-A reasoner; ollama is the weakness-profile target).

---

## § User-added

1. I don't understand the purpose of .k4k/version/<n>/

Is it to be considered as a working copy for the development of version <n>, a bit like a git branch used during the development? If so, I assume that when the version development is completed, the source code will be pushed to the main branch repository for artefact distribution? I would find this meaningful: essentially we have a monorepository for development that contains repositories used for publication of source file and distribution of packages in the standard way it is done today in the industry.

2. How do we prevent the .k4k to contain to much information for the user?

Too much information will make the user attention less efficient. Should k4k maintain in the .k4k file only the global context and the information related to the current development and keep links to files containing the previous content of the k4k but that is now stable because the corresponding versions are implemented?
