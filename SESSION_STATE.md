# SESSION_STATE — 2026-06-20 (autonomous build)

## end-to-end CERTIFY back-end (ralph loop)  ← v1 DONE-BAR ACHIEVED, audited GREEN

**ACHIEVED:** `k4kspec certify <file.k4kspec>` produces a coqc-checked, extracted, runnable
**certified** binary + TCB manifest. **ALL SIX example specs certify green** across the whole
v1 fragment — no-file (`upper`, `greet`), single-file (`grepf`, `kvget`, `cutf`), and variadic
(`catf`). FOUR independent fresh-agent audits returned GREEN, each with tamper tests proving the
proof is non-vacuous (corrupting `run` makes coqc reject it). Try:
`dune exec k4kspec/bin/main.exe -- certify k4kspec/examples/grepf.k4kspec` then
`/tmp/k4k_certify/grepf an <some-file>`. Plan + audit criteria + done-bar: `k4kspec/backend/PLAN.md`.
**Feasibility PROVEN** by a hand-written PoC (`k4kspec/backend/poc/`): coqc checks the proof
(no Admitted/Axiom), extraction works, the `upper` binary runs (`upper hello -> HELLO`, exit 0).
Rocq 9.1.1 + Z3 are installed. Ralph-loop protocol: each iteration do the next milestone,
commit, then a FRESH agent audits (criteria in PLAN.md §Audit); fix until a fresh-agent audit is
GREEN, then emit the completion promise. **Loop state below is updated each iteration:**

### Certify-pipeline progress log (newest first)
- 2026-07-10 (later): **v3 PRODUCTIZATION — the full PRD loop shipped on the k4kspec core
  (ADR-022; commits 271990d..).** Approved plan executed in 8 milestones, each green+committed:
  M1 laws in the surface language (per-case `law` stmt; output-refs only in laws, statically
  checked; 4 law built-ins as surface files, emit byte-identical). M2 record.ml (one machine-
  record format) + quiet Check.report. M3 sign/store: <name>.k4k/ ledger; BLAKE256 signatures =
  version history w/ chain; under-spec ack (exit 4); certify GATED (exit 3; --unsigned = stamped
  dev run); Kalgebra EMBEDDED in the binary (product runs from any cwd). M4 tier waivers (laws
  only; single choke point; fully-waived spec fails check BY DESIGN). M5 certificate.md: computed
  scope table (CERTIFIED / CERTIFIED-BY-LAW / FREE / WAIVED), waiver disclosure derived from the
  same record that weakens (cannot diverge), promotion into certificates/v<N>/. M6 propose/
  revise/propose-fix: retry-gated (structure→parse→check→decisions-monotone), monotonic immortal
  decision journal, deterministic stubs = whole loop agent-free-testable, mechanical delta +
  line diff, last-failure.md + propose-fix. M7 LIVE DEMO all green: propose "grep -F clone" →
  signed-quality draft attempt 1 → sign v1 → live proof attempt 1 (60/60) → promoted certificate
  → forced failure → live propose-fix (honest cost analysis) → live revise invented 7
  interlocking laws (anti-smuggling + canonicality) when the vocabulary lacked int→string;
  monotone decisions held; unelaborable draft CONTAINED by the honesty chain (check flags → sign
  refuses). M8 fresh-agent audit RED→FIXED: read-twice TOCTOU in the gate (certify could prove
  bytes never signed under a race) → read-once (verify_bytes + single buffer), strace-verified
  1 open; all other attacks mitigated. Tests 100+ checks ALL OK; kb-lint errors at baseline.
  DEFERRED (recorded in ADR-022): v2 watcher retirement pass (README/WALKTHROUGH/opam still
  describe v2); accept-a-proposal command (mv is the acceptance act); tier-B/C execution;
  guidance→R conflict check; elaborate-dry-run gate in revise; propose name path-guard;
  int→bytes rendering in the algebra (the revise demo wanted it).
- 2026-07-10: **grepsort CERTIFIED — first BREADTH+DEPTH certificate; recursive fill realized
  (ADR-021's top two open items closed).** Commits: 572e73a (certificate gate), a3a4dbb (spec:
  bytes_le + sorted_lines + grepsort), da3dea9 (recursive per-lemma fill), + this landing.
  ARC: (1) monolithic component fill stalled one tactic short (ADR-020's failure shape at module
  level); (2) rebuilt as RECURSIVE fill — one `Lemma … Admitted.` span agent-replaced+spliced at a
  time, ≤3 focused attempts w/ per-lemma coqc feedback, one kernel-gated skeleton escalation per
  lemma, helpers re-enter the loop, total-budget bound, honest per-lemma failure (same ladder as
  the agentic-dev-kit escalation contract); (3) run 1 (budget 24): sort proved in 2 calls — the
  DEPTH was the lines/unlines/splitc roundtrip (needs a discovered no-embedded-newline side
  condition); cascade converged but exhausted budget 5 lemmas short; (4) documented the algebra's
  POSIX semantics in kalgebra_blurb (3 lines) + budget 48 → run 2 closed GREEN in 12 calls,
  1 escalation. L20: documenting the trusted vocabulary beat the budget increase. Certificate:
  4 components; agent invented boolean lex comparator blexb + insertion sort + the Forall
  side condition; statement-pin gate + Print Assumptions closed; binary byte-identical to
  `grep -F | sort` on all probes incl. no-trailing-newline and empty-needle/empty-line; 3+5
  body-only tampers rejected (tamper-design lesson: verify the sed changed the BODY only — a
  no-op or statement-touching tamper proves nothing); fresh-agent audit GREEN (bytes_le proven
  reflexive/total/transitive/antisym; laws pin output uniquely up to one trailing newline —
  accepted; recursive-fill heuristics can only false-negative, never false-certify; manifest
  provenance accurate; 21/29 cross-check categorization verified genuine).
  NEXT (ADR-021 open): certified-component library (harvest grepsort's proven splitc/lines/unlines
  lemmas into Kalgebra as blessed PROVED laws — zero TCB growth); inter-component dependency
  ordering; deeper recursion stress. Backlog: law-aware `check` front-end; kb/ lint debt (142).
  FOLLOW-UP same day: library harvested (commit 9d75932 — lines_unlines + lines_no_newline +
  splitc laws in Kalgebra's PROVED-LAWS section, blurb advertises them). Run 3 = the compounding
  test: GREEN in 6 calls, 0 escalations, every component first-try — run 1's budget-consuming
  roundtrip is now `apply lines_unlines. Qed.`, the glue cites lines_no_newline for the side
  condition. Trajectory 24-FAIL → 12 → 6 (L23: certificates mint lemmas; harvest each one). Law-aware check DONE: `Eval.Undetermined idx` distinguishes matched-but-
  law-constrained from no-match; check reports "law-constrained inputs: N (proof-guaranteed via
  certify)" instead of a false exhaustiveness FAIL, law cases aren't "dead", ANY-with-laws is
  "constrained by N law(s)" not a vacuity WARN; bsort/partition/usort/grepsort now check-exit 0
  (determined specs unchanged); `run` on a law case explains and points to certify-agent.
- 2026-07-08: **usort LANDED + re-validated (provenance gap closed); manifest honesty fix.**
  Audit found the 2026-06-20 usort result's spec artifacts (usort in `specs.ml`,
  `sorted_strict`/`same_set` in `rocq_emit.ml`, `ascii_lt` in `Kalgebra.v`) were NEVER committed —
  the KB claimed a result git couldn't reproduce. Landed as a first-class built-in and re-certified
  via `certify-agent --structured usort` (tools-off claude): implement/skeleton/fill ALL attempt 1,
  ONE fill round. NEW DATAPOINT (L18): the agent invented a proof-friendlier ALGORITHM this time —
  `filter (∈ input) (map ascii_of_nat (seq 0 256))`, sorted+dedup BY CONSTRUCTION, 6 lemmas vs
  June's ~10-lemma insertion-sort+dedup. Validation: Print Assumptions closed; 3-way tamper test
  non-vacuous; binary correct on 6 probes. Fresh-agent audit GREEN and unusually strong: Coq
  META-PROOF that the two laws uniquely determine the output; ascii_lt proved a strict total order
  with Sorted→NoDup; 5 novel gate attacks rejected (axiom-smuggling caught by Print Assumptions,
  ascii_lt shadowing, guard weakening); 16/16 vs an independent byte-level oracle incl. raw
  non-UTF-8 bytes. Audit findings: (1) FIXED — TCB manifest's hardcoded Limitation line was false
  for agent-produced certificates (certify_v now takes ?limitation; agent paths pass provenance
  text). (2) FIXED (and it was worse than the audit thought): a live attack showed a vacuous
  `Theorem correct : True.` passed EVERY gate on an under-determined spec — an echo binary was
  "certified" as usort (nothing pinned WHAT was proved; Print Assumptions alone would NOT have
  caught it, True's proof is closed). certify_v now compiles a harness-authored gate file:
  `Check (correct : forall i, spec_rel i (run i))` pins the statement + `Print Assumptions` must
  be Closed (catches Axiom<tab> spelling evasion, demonstrated); Extract-class vernacs banned.
  Echo + tab-axiom attacks now FAIL; deterministic/stub/prior paths pass; tests ALL OK.
  (3) OPEN (pre-existing): the `check` front-end predates laws — bsort/partition/usort all exit 1
  with misleading diagnostics ("matched NO case"/"dead case" for law-cases); teach check to report
  law-cases as proof-guaranteed. (4) Vendored agentic-dev-kit is 1 commit behind canonical
  (~/work/dev/agentic-dev-kit @953c455 adds kb-lint + KB-enforcement); kb/ has 142 pre-existing
  lint errors (frontmatter schema, dangling links, >200-line files) — separate cleanup task.
  NEXT: Phase B — breadth+depth in ONE target (grep-then-sort pipeline) via
  `certify-agent --compositional`, per ADR-021 "Open/next".
- 2026-06-21: **FIRST MULTI-MODULE certificate — grepf, 5 agent-chosen components.** `certify-agent
  --compositional grepf` (claude, tools off) certified the grep-class spec by decomposing it into
  FIVE components — comp_argc (arg count), comp_nofile (file-absent test), comp_match (matching lines
  = filter-by-contains over lines), comp_err (error output), comp_ok (success output) — each with a
  functional contract + certificate; run composes them; the glue proves the top observational spec
  from the five contracts ALONE. Module-interface gate passed attempt 1; 0 escape hatches; binary
  MATCHES 39/39; independently re-checks (Print Assumptions = Closed under global context). Human
  signs ONLY the top spec_rel. Reference: `k4kspec/backend/poc/grepf_compositional.v` (commit
  0b4364d). Validates multi-module BREADTH (module graph + contract glue) on a grep-class program;
  DEPTH shown separately (bsort sort component, usort). NEXT: breadth + a deep component (grep-then-
  sort pipeline); recursive decomposition; certified-component library.
- 2026-06-21: **AGENT-DRIVEN COMPOSITIONAL certification (ADR-021 follow-on) — built + validated.**
  `certify-agent --compositional` (`lib/agent_proof.ml:certify_compositional`): PHASE A decompose
  (agent proposes components [impl + functional contract] + run-as-composition + glue) gated by the
  MODULE-INTERFACE GATE (coqc accepts the glue Qed'd with component certs Admitted) → PHASE B certify
  each component (drive compK_correct admits→0) → PHASE C assemble + certify_v. ADR-020's structured
  method generalized to module boundaries. **bsort certifies compositionally**: claude DROVE a genuine
  2-component decomposition (sort_chars:bytes→bytes contract Sorted/\Permutation; err_line:unit→bytes
  contract one_nonempty_line), run composing them, glue deriving the top spec from the two component
  certificates; module-interface gate passed attempt 1; 0 escape hatches; binary correct. Commit
  ec74442. Validates the machinery (small spec; scaling payoff is on large multi-module targets).
  Next: a first genuinely multi-module target; recursive decomposition; certified-component library.
- 2026-06-21: **COMPOSITIONAL CERTIFICATION (ADR-021) — architecture + validated prototype.** Yann's
  forward-looking concern: real targets (a grep clone) need modular architecture to scale, even under
  KISS. **ADR-021:** the human signs ONLY the top observational `spec_rel` (stays flat regardless of
  impl size); the implementation scales on two impl-side axes — (1) compositional verification (`run`
  = composition of certified components, each a FUNCTIONAL Coq contract `forall x, S x (f x)`,
  agent-proposed + kernel-checked, NOT human-signed; ADR-020's skeleton gate generalizes to a
  MODULE-INTERFACE GATE), (2) naive->efficient refinement (we certify the simplest correct impl, not
  20kloc of perf engineering). Contract form DECIDED: functional Coq relations (components are
  functions, not CLI programs). **Prototype `k4kspec/backend/poc/compose_sort.v` (coqc exit 0):**
  `run = format o core` certified from two component contracts (core=sort: Sorted/\Permutation;
  format=string_of_list_ascii: roundtrip); GLUE `compose` derives the top byte-level spec from the two
  certificates only — `Print Assumptions compose` = Closed under the global context (0 axioms). Plus
  the MODULE-INTERFACE GATE (`acompose`, Section AbstractComposition): the top spec proven with
  components UNINTERPRETED + contracts as hypotheses — the decomposition is kernel-valid BEFORE any
  component is built. Commits bee7000 (ADR-021) + fc41c36 (poc). **Follow-on:** wire compositional
  decomposition into the agent backend (agent proposes components+contracts+glue; harness drives the
  module-interface gate + recursive structured certification).
- 2026-06-20: **STRUCTURED PROOF METHODOLOGY (ADR-020) built + validated — unblocks usort.** Yann's
  redirection: design a methodology before brute-forcing hard proofs. Approved: skeleton-gate + fill,
  correctness-only. `certify-agent --structured <spec>` (`lib/agent_proof.ml:certify_structured`,
  `Certify.coqc_check`): PHASE 1 implement-naive (typecheck gate) → PHASE 2 SKETCH (the keystone:
  coqc checks the lemma decomposition with lemmas Admitted → plan certified type-correct & sufficient
  before any lemma is proved) → PHASE 3 fill (admits→0, focused feedback) → PHASE 4 certify_v (bans
  admits; real certificate). Live per-phase stderr progress. **`usort` (multi-invariant; one-shot
  STALLED, no candidate in 45min) now CERTIFIES**: claude decomposed into ~10 lemmas (insertA/isortA
  sort+dedup; insertA_sorted/isortA_sorted strict-sort; insertA_in/isortA_in/nat_of_ascii_inj
  set-equality); 0 escape hatches; binary banana→abn. Commits 93bed17 (ADR-020) + 6e9f3ae (build).
  One-shot path retained as fallback. NOTE cosmetic: live stderr + final stdout log both show under
  2>&1 (harmless). Built-in specs: grepf/cutf/catf/kvget/bsort/partition/usort (upper/greet are FILES).
- 2026-06-20: **NON-SORT hard proof closed (attempt 1) — bet generalizes beyond memorized proofs.**
  New spec `partition` (stdout = a permutation of argv[0]'s bytes, PARTITIONED around 'm'=109,
  expressed as `Sorted part_le` for the implication-preorder `part_le` in Kalgebra — NOT a stdlib
  order). Deterministic `certify partition` FAILS. `certify-agent partition` (claude, tools off):
  closed on ATTEMPT 1 with genuine reasoning — impl `filter(<109)++filter(>=109)`; proof via
  `StronglySorted`, the VACUOUS-TRUTH argument for part_le on the big group, `Permutation_cons_app`
  for partition-is-a-permutation, the roundtrip lemma; 0 escape hatches; binary `azbymc -> abczym`.
  Commit fa0a30b. This is proof CONSTRUCTION over an unfamiliar relation, not retrieval — the
  central bet holds on a second, non-sort, less-canned proof shape.
- 2026-06-20: **HARD relational proof WORKS — the bet holds on the genuinely-hard case.** Added
  relational LAWS (AST output-refs `OStdout/OStderr/OExit` + per-case `laws`; `Sorted`/`Permutation`
  + `ascii_le` in Kalgebra; rocq_emit emits laws into spec_rel + supports under-determined `P Any`
  channels; certify_v reports checked-vs-under-determined honestly; `agent_proof.clean` strips prose
  around unfenced Coq). New spec **`bsort`** (NoFiles): stdout's bytes are a SORTED PERMUTATION of
  argv[0]'s bytes — UNDER-DETERMINED (only a law), so the deterministic generator CANNOT do it
  (`certify bsort` FAILS, as it must). **`certify-agent bsort` with `claude -p --allowedTools ""`:
  claude INVENTED insertion sort and PROVED `forall i, spec_rel i (run i)` by induction**
  (insert_perm/isort_perm/HdRel_insert/insert_sorted/isort_sorted + the roundtrip lemma); coqc
  CLOSED it on attempt 2 (attempt 1 rejected → error fed back → fixed; the retry loop earning its
  keep). Certified binary sorts: `bsort dcba -> abcd`, `bsort hello -> ehllo`. Independently
  re-verified under coqc (no Admitted/Axiom). Commits 2b44787 + the test fix. **Harness fixes that
  mattered:** run the agent with TOOLS OFF (`--allowedTools ""`, else `claude -p` tried to compile
  itself and emitted prose) + `clean` strips prose. **This answers the open question: the agent can
  close a real inductive equivalence proof, not just case-split pinned specs.**
- 2026-06-20: **AGENT PROOF BACKEND realized (ADR-019) — the central bet works.** `certify-agent
  <file>`: the elaborator fixes the certified statement `spec_rel`; an external agent
  (`$K4K_PROOF_CMD`, e.g. `cd /tmp && claude -p`) proposes `run` + a Coq proof; **coqc is the only
  gate** (+ banned-word gate), with error-feedback retries. **claude closed a real proof on
  `upper`** — a `run` with INVERTED branch structure + its own minimal error message (genuinely
  different from the spec), accepted by coqc on attempt 1; binary matched on 15 inputs. Gate
  verified: wrong run / non-closing proof → coqc rejects → FAILED; `Admitted` → banned-gate →
  FAILED. The agent supplies ONLY run+proof against the FIXED spec_rel (can't weaken what's
  certified). `lib/agent_proof.ml`; `certify_v` refactor; commit 01ecdb8. **HONEST LIMIT:** `upper`
  is the easiest spec; whether LLMs close HARD proofs (induction over lines/filter; optimised
  impls) is the open empirical question — the harness now makes it measurable. **Also (ADR-018):**
  TCB shrunk — blessed algebra is audited-once `backend/Kalgebra.v` (commit 63ee151); realized-v1
  captured in the KB (ADR-018, PRD, INDEX).
- 2026-06-20: **M4 COMPLETE — ALL SIX example specs certify GREEN, fresh-agent audited.** Added
  `kvget`+`cutf` (Rocq `split`/`get`/`first`/`any`/`int_of`/`is_decimal`) and `catf` (VARIADIC:
  `Input.contents:list(option bytes)`, `fold_left`/`existsb` over the pre-read contents). Two more
  independent audits (kvget+cutf, then catf+full-regression) returned GREEN with tamper tests
  proving non-vacuity. Commits c7d7536, de9ebb8. Whole fragment certified: no-file (upper,greet),
  single-file (grepf,kvget,cutf), variadic (catf). **Variadic caveat (documented):** the
  file_at-over-argv rewrite assumes the argv element is used ONLY via file_at (the canonical
  variadic pattern). **Remaining big items:** the agent-driven (stochastic) PROOF backend for
  hard proofs where `run` differs from the spec (the central bet); verified extraction / TCB
  shrinking (panel actions); fold the certify pipeline into the KB/PRD as realized-v1.
- 2026-06-20: **M3 DONE — `certify grepf.k4kspec` GREEN, fresh-agent audit GREEN. DONE-BAR MET.**
  Automated `certify` now produces a coqc-checked, extracted, runnable CERTIFIED binary for BOTH
  the no-file fragment (`upper`) AND the file-handling fragment (`grepf`). Independent auditor
  confirmed: 3-way tamper test on grepf's `run` → coqc rejects each (non-vacuous); the binary
  matches the spec on real files incl. trailing-newline / empty-line edge cases; 0 mismatches
  over 39 inputs; manifest honest; 3 distinct generated `.v`. **END-TO-END v1 RUN ACHIEVED;
  promise V1_E2E_GREEN emitted.** rocq_emit.ml now does the file algebra (lines/contains/unlines
  + lambdas + a type env); certify.ml has the file shim + file-materialising cross-check.
  Remaining (future, M4+): variadic + `get`/`split`/`int_of`/`fold`/`first`/`any` for
  kvget/cutf/catf; and the agent-driven (stochastic) backend for HARD proofs where `run` must
  differ from the spec (v1 generates `run` to match the spec, so proofs are easy — honest limit).
- 2026-06-20: **M1+M2 DONE — fresh-agent audit GREEN.** `k4kspec certify <file.k4kspec>` now
  automates emit -> coqc -> extract -> compile(+shim) -> run -> cross-check(oracle) -> manifest
  for the **NO-FILE** fragment. `certify upper.k4kspec` and `certify greet.k4kspec` both green
  (coqc proof CHECKED, no Admitted/Axiom; binary matches the spec on 15 inputs; the two
  generated `.v` DIFFER, so the elaborator is general). An independent auditor confirmed
  **non-vacuity** by tampering `run` 3 ways -> coqc correctly REJECTS each. Files:
  `lib/rocq_emit.ml` (elaborator), `lib/certify.ml` (driver), `bin/main.ml` (`emit`/`certify`),
  `examples/{upper,greet}.k4kspec`. (Fixed: `Abort` added to the certify banned-list.)
  Try: `dune exec k4kspec/bin/main.exe -- certify k4kspec/examples/upper.k4kspec`.

  **NEXT: M3 — the FILE-HANDLING fragment, so `certify grepf.k4kspec` goes green (the done-bar
  for the V1_E2E_GREEN promise; do NOT emit the promise until a fresh agent confirms grepf).**
  Design notes for M3 (in `rocq_emit.ml` + `certify.ml`):
  - Specialise `Input` to the footprint: `FileAt i` adds a field `file1 : option bytes` (the
    file shim reads `argv[i]` -> `Some content` / `None` if absent). Translate `file absent`
    -> `(match file1 i with None => true | _ => false)`; `file.bytes` -> a total accessor
    `(match file1 i with Some c => c | None => EmptyString end)`.
  - Port the blessed algebra to Rocq: `lines`, `split`, `contains`, `unlines`, `filter`/`map`/
    `fold` (combinators take a Rocq `fun`), `get`, `first`, `is_decimal`, `int_of`, `file_at`,
    `opt_bytes`. grepf needs only: `lines`, `filter`+lambda, `contains`, `unlines`, `is_empty`.
    The Rocq defs MUST match `lib/algebra.ml` (esp. `lines` POSIX trailing-newline rule).
  - Lambdas: `rocq_emit.re (Lam(x,body))` -> `(fun x => <body>)`; `Var x` already works.
  - File shim (variant of the no-file one): build `Input` with `file1 = read_opt argv[i]`;
    open ONLY the footprint paths (frame by construction).
  - Proof: the generic case-split tactic already destructs inner `if`s (e.g. grepf's
    `if is_empty matched then 1 else 0`). May need `cbv zeta`/`cbn` to settle `let`s before
    `reflexivity` — adjust the tactic if coqc complains. Test on grepf iteratively.
  - Then M4 (kvget/cutf/catf), M5 (manifest/docs). Audit each milestone with a FRESH agent.
- 2026-06-20: PoC proven (`backend/poc/upper.v` coqc-green + extracted binary runs). Plan
  (`backend/PLAN.md`) written. Ralph loop armed (max-iterations 40, promise V1_E2E_GREEN).

---

## What I built (and why this, not "v1 of k4k")

A **reference-free spec-validation core** for k4kspec — the panel's #1 highest-leverage,
lowest-risk, most-tangible piece, and the one with **no formal-methods dependency** to get
stuck on. It is the *front-end* of v1 (validate a spec against intent), **not** the
certifying back-end (Rocq proof + extraction + certificate), which is weeks of work and
rides the project's central unproven bet — I deliberately did not attempt it.

After your interrupt ("cloning X was only an example"), I recalibrated: the spine is the
**general, reference-free** validation loop where the **human is the oracle of intent**.
Differential testing against a real binary is an *optional clone plug*, clearly labelled.

Everything is in a fresh `k4kspec/` tree, **stdlib-only**, untouched by the (alcotest-broken)
v2 build.

## How to test it (start here)

```sh
cd /mnt/archive/yann/new-home/perso/dev/k4k

# unit tests (stdlib-only, no alcotest):
dune build @k4kspec/test/runtest        # prints "ALL OK"

# the validation harness on the NON-clone spec (no reference tool involved):
dune exec k4kspec/bin/main.exe -- check kvget

# the others:
dune exec k4kspec/bin/main.exe -- check grepf
dune exec k4kspec/bin/main.exe -- check cutf
dune exec k4kspec/bin/main.exe -- check catf

# validate a .k4kspec FILE (write your own — examples in k4kspec/examples/):
dune exec k4kspec/bin/main.exe -- check k4kspec/examples/kvget.k4kspec

# execute a spec as its own model:
printf 'apple\nbanana\ncherry\n' > /tmp/fruit.txt
dune exec k4kspec/bin/main.exe -- run grepf -- an /tmp/fruit.txt   # -> banana

# OPTIONAL clone plug (special case): diff a spec vs a real tool
dune exec k4kspec/bin/main.exe -- check grepf --ref 'grep -F'
```

`check <name>` reports: **examples** (the author's stated intent), **stability**
(exhaustiveness, dead-case heuristic, anti-vacuity), **under-specified dimensions**
(free channels, for explicit sign-off), and an **adversarial sweep** (the spec's behavior
on boundary inputs — *review these: is this what you meant?*). Exit 0 iff it validates.

## What the run already surfaced (the harness earning its keep)

- **`cutf` flagged case #4 (absent-file) as possibly-dead** — neither the examples nor the
  sweep exercised "valid args + absent file". I added the missing example; flag cleared.
  (This is the coverage-gap surfacing working.)
- **clone diff `grepf` vs `grep -F`** found a real semantic divergence: my `grepf` requires
  2 args (exit 2 on one), while `grep -F NEEDLE` reads **stdin** (exit 1). Legitimate design
  difference — exactly what differential testing is for, *when* you're cloning.
- **`grep` on this machine is ugrep 7.5**, not GNU grep (`cut`/`cat` are GNU coreutils 9.10).
  A live instance of the "*which* tool are you cloning?" clarification.

## What is intentionally NOT here

- No Rocq / proof / extraction / certified binary (the back-end; out of scope for 2h).
- `run`'s stdin is empty (none of the 4 specs read stdin); wire real stdin when a spec needs it.
- The blessed algebra has no int->bytes rendering or take/drop/slice yet (grow by need).

## Decisions I made autonomously (all reversible; recorded here + in memory)

- Bytes = OCaml `string` (8-bit clean). Algebra is total + byte-first (`k4kspec/lib/algebra.ml`).
- `lines` = documented POSIX (final `\n` is a terminator, not an empty trailing line);
  `split` is mechanical (keeps every piece). Tested in `test_k4kspec.ml`.
- kvget value = field after the FIRST `=` only (so `k=a=b` → `a`); a defined choice for the demo.
- The adversarial generator is a deterministic heuristic (no randomness); dead-case detection
  is explicitly labelled "heuristic, over sweep" — it can false-positive (as cutf #4 showed).

## Module map (`k4kspec/`)

| file | role |
|---|---|
| `lib/algebra.ml` | the blessed value algebra (total, byte-first) — the audited-once TCB core |
| `lib/ast.ml`     | spec AST (Input/Output, cases/lets/outs, footprint, examples) |
| `lib/eval.ml`    | the spec **oracle**: run a spec → determined (stdout, exit) + stderr constraint |
| `lib/specs.ml`   | grepf / cutf / catf / **kvget** (non-clone) as AST values, with examples |
| `lib/check.ml`   | the reference-free harness (examples / stability / under-spec / sweep). The sweep includes **mutations of your own examples** (drop/add an arg, empty a file, toggle trailing newline, remove a file) — the most relevant boundaries — plus a generic boundary grid |
| `lib/parse.ml`   | surface `.k4kspec` text -> AST (lexer + recursive-descent parser; located `line:col` errors). Round-trip tested against the AST specs |
| `lib/refdiff.ml` | OPTIONAL clone differential vs a reference binary (special case) |
| `bin/main.ml`    | CLI: `list` / `check` / `run` |
| `test/test_k4kspec.ml` | stdlib-only tests (algebra + oracle + all examples + exhaustiveness) |

## Next steps (in leverage order)

1. ~~Surface parser~~ **DONE** (`lib/parse.ml`; `line:col` errors; round-trip tested). `check`/`run`
   take a `.k4kspec` file or a built-in name.
2. **Pin the blessed-def semantics** precisely (Rocq defs + English contract) — they are the
   certified vocabulary (ADR-016 / spec/k4kspec.md §8).
3. Grow the algebra as real specs demand it (int->bytes rendering, take/drop/slice, …).
4. Smarter property generation (shrinking, guard-aware boundary mining) for the sweep.
5. Then the certifying back-end (elaborate → Rocq `spec_rel` + theorem + shim + extraction).

KB for the design behind all this: `kb/INDEX.md` → ADR-014/015/016/017, `kb/spec/k4kspec.md`,
`kb/reports/expert-panel-2026-06-19.md`.
