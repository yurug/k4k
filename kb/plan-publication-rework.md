---
id: plan-publication-rework
domain: planning
last-updated: 2026-07-22
related: [prd, notes, adr-022]
---

# Publication rework plan — k4k as the killer app

Context: the blog series *Software engineering in the agent era* (see
`~/perso/doc/blog/kb/notes/revision-2-living-essays.md`) uses k4k as its
Ariadne's thread: the concrete, runnable demonstration of the four-discipline
process (software, knowledge, harness, engineer engineering). The hub essay
publishes only once this repo is public and presentable, with a call to action
pointing here. This plan defines the rework. It is a demonstration-tool
cleanup, not a feature program: the repo must show the approach with no noise,
not narrate every step that led to it.

## Current state (verified 2026-07-22)

- **v3 `k4kspec/` is the product**: spec-validation + certification CLI
  (`list`, `check`, `run`, `emit`, `sign`, `status`, `certify`,
  `certify-agent`, `propose`, `revise`, `propose-fix`). Stdlib-only OCaml;
  builds clean; `test_k4kspec` ALL OK; 8 built-in specs (grepf, cutf, catf,
  kvget, bsort, partition, usort, grepsort); Rocq backend (`Kalgebra.v`,
  non-vacuous theorems, extraction, oracle cross-check, TCB manifest, signed
  certificate ledger). ADR-022 declares the v3 product surface realized.
- **v2 watcher stack is superseded and broken in the current switch**: `lib/`
  (~90 files), root `bin/main.ml`, `prompts/`, `test/{unit,integration,edge,
  conformance}` (~7.6k LOC), `examples/backends/`, `examples/scenarios/`.
  Missing deps (fpath, digestif), cmdliner version mismatch. ADR-022 already
  names a "v2 watcher retirement pass" as deferred work.
- **Top-level docs describe v2, not the product**: `README.md`,
  `WALKTHROUGH.md`, `k4k.opam` (v0.2.0) still present the watcher-daemon
  vision (cotype, Tier A/B/C, trade-off sign-off).
- **No git remote**: the repo is local-only. 171 commits, clean tree, last
  commit 2026-07-10.
- **kb debt**: 142 kb-lint errors (frontmatter schema, dangling links,
  oversized files); `kb/archive/v0-drifted/` deliberately quarantined.
- **No mention of rocqeteer anywhere in this repo** (and none of k4k in
  rocqeteer).

## Workstreams

### W1 — v2 retirement pass

Delete the superseded v2 stack: `lib/`, root `bin/`, `prompts/`,
`test/{unit,integration,edge,conformance}`, `examples/backends/`,
`examples/scenarios/`. Git history is the archive; no attic directories. The
concepts worth keeping (trade-off sign-off, tier model) are already recorded
in the ADRs. Promote `k4kspec/bin` to install as the `k4k` binary (naming to
confirm, see Open questions). Rewrite `k4k.opam` for v3: stdlib-only OCaml,
document the external `coqc`/`rocq` requirement, bump to 0.3.0.

### W2 — story and docs rewrite

- New `README.md` telling the v3 story only: the thesis (a KISS program
  deserves a stupidly simple agentic development: sign a spec, prove one
  theorem that the program does one thing and does it well), a five-minute
  demo (`check` → `sign` → `certify` on one built-in), the certification
  pipeline and its TCB stated honestly, and the scope statement (KISS is a
  proving ground, not a universal doctrine).
- Vocabulary aligned with the blog glossary (`~/perso/doc/blog/kb/GLOSSARY.md`):
  four disciplines, harness, KISS scope, local explainability. The README is
  the practical companion of the blog series and links back to it.
- Replace `WALKTHROUGH.md` with a v3 demo transcript.
- kb pass: fix the kb-lint errors that affect navigation (INDEX, dangling
  links); register this plan in `kb/INDEX.md`; leave `kb/archive/` quarantined.

### W3 — rocqeteer spike: UNIX-like KISS programs

rocqeteer (github.com/yurug/rocqeteer, public, BSD-3-Clause, copyright Nomadic
Labs) is a certified pipeline from effectful Rocq programs (EffIR + reference
interpreter) to idiomatic OCaml 5 effects, differentially tested, with a TCB
report. It already ships a proven `wc` and a proven HTTP/1.0 server built as
"certified core + thin untrusted argv/exit-code wrapper", and a file I/O
effect family that models argv, env, stdin/stdout and proves chunking
invariance.

Overlap and complement with k4k today: k4k owns the **spec language, signing,
certification ledger, and agent-driven proving** (the harness and process
side); its extracted programs run behind an untrusted I/O shim. rocqeteer owns
**proven effectful semantics and certified codegen** (the execution side).
Hypothesis: stating k4kspec semantics against rocqeteer's EffIR reference
interpreter would give certified k4k tools real file/stdin/stdout behaviour
with proven equivalence, replacing the shim, and would reuse rocqeteer's
differential harness against coreutils.

Spike, strictly bounded: re-certify **one** built-in (catf or grepf) through
EffIR end-to-end, then decide: adopt as the execution backend / keep as an
interop demo / defer. Known rocqeteer gaps to respect: no pipes yet, bounded
input sizes, concurrency only proposed (ADR-0019). Licensing is compatible
(BSD-3 is permissive; retain the notice); the dependency also makes a good
story: two certified toolchains, one personal, one from work, composing.

### W4 — local-explainability experiment

Host the explanation-length cohesion experiment defined in the blog plan
(`revision-2-living-essays.md` § The explanation-length cohesion experiment):
minimal correct explanation length of a module's role, under adversarial
fidelity checks, as a cohesion measure. Suggested shape:
`experiments/local-explainability/` with a small driver; first subjects: k4k's
own modules and rocqeteer's tools. Its output is the dataset the blog's
software-engineering essay needs. Not a gate for the hub, but a gate for that
essay.

### W5 — publication

Create the GitHub repo (`yurug/k4k`), add LICENSE (see Open questions), CI
(build + tests + one `certify` smoke run, no agent-driven proving in CI), tag
v0.3.0. This closes the blog's hub gate ("public and presentable").

## Sequencing and gates

- Critical path for the blog hub: **W1 → W2 → W5**. W3 and W4 run parallel and
  gate only the software-engineering pillar essay (first experiment numbers)
  and possibly a later k4k version.
- Each workstream lands as its own commit series with green
  `dune build k4kspec/... && dune exec k4kspec/test/test_k4kspec.exe`.
- Blog-side mirror of these gates: `revision-2-living-essays.md` § Tool
  releases.

## Open questions (author)

1. **Binary and repo name**: install the CLI as `k4k` (recommended) and name
   the GitHub repo `k4k`? (`k4kspec` remains the language/file-format name.)
2. **License**: BSD-3-Clause (matches rocqeteer) or MIT? Needed before W5.
3. **v2 salvage check**: anything in the watcher stack worth keeping beyond
   what the ADRs record, before W1 deletes it?
4. **rocqeteer adoption depth**: is "execution backend" the ambition if the
   spike succeeds, or is an interop demo enough for the series?
