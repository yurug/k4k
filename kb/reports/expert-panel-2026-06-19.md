# k4k spec-language approach — 10-expert verification panel

_Generated 2026-06-19 via the `expert-verification-panel` workflow (run wf_5e3e2f9d-519). Each review was independently web-researched and its citations skeptically fact-checked. Personas channel the named researchers' published positions; they are characterizations, not quotes._

## Synthesis

I'll synthesize the panel. Let me note the citation flags upfront: Rod Chapman's [5] is flagged (misattribution + mischaracterization), and Talia Ringer's [3] has a minor year slip (paper genuine). All other experts are solid or minor-issues-with-no-flags. Let me produce the synthesis.

# k4k Panel Synthesis — Actionable Guidance

All ten experts independently converge on one structural verdict: **the proof is the easy leg; trust collapses onto the human-signed spec and the unverified perimeter (elaborator, I/O shim, value algebra, extraction).** k4k has heavily engineered the prover gate and under-engineered the spec-validation and TCB-honesty legs. The refinements below are ordered by how many experts demand them and how much they move k4k's actual trust.

---

## CONVERGENCE

### 1. Mechanize spec-vs-intent validation — make the spec software-under-test (HIGHEST LEVERAGE)
**What to change:** STABILITY today is well-formedness (parse/type/exhaustive/consistent/examples-agree). It must be joined by a *validity* phase that mechanically attacks "is R what the human meant?" Since R is executable (totality via exhaustive guards), the harness should: (a) compile k4kspec to an executable oracle and run adversarial/differential/random inputs through it *before* any proof is attempted; (b) for fully-determined cases, differentially test R against the extracted implementation; (c) auto-generate adversarial counterexamples *outside* the author's EXAMPLES set and surface disagreements to the human reviewer to adjudicate.

**Who backs it:** Leroy ("Test executable forms of the specifications"; reference interpreter), Pierce (QuickChick PBT *on the spec*; "test the spec before you trust the proof"), Swamy (3DGen: human-authored reference specs were wrong, caught only by symbolic differential testing against an external oracle), Klein (spec validation as a first-class phase distinct from verification), Ringer (auto-generate adversarial counterexamples; Baldur repair signal), Lamport (force adequacy evidence, not totality), Leino (Clover-style consistency), O'Hearn (diff-time spec review). **8 of 10 experts.**

**Why it matters:** A proof of `∀i. R i (run i)` certifies the implementation against R, never R against intent. Swamy's and Leroy's direct experience: trained authors wrote *wrong reference specs for simple formats*, undetected by reading, detected only by executable differential testing. This is the single highest-leverage gap because it attacks the leg that every other expert agrees is load-bearing and currently unguarded by anything mechanical.

### 2. Add an anti-vacuity / non-triviality obligation (dual of the consistency check)
**What to change:** STABILITY checks "no input forced to an empty acceptable set" (R non-empty) but not the dual: an R that accepts *everything* for some input, a CASE whose guard is unreachable, or a LAW whose hypothesis is never satisfiable. Add a *mandatory* obligation: prove R is satisfiable AND exhibit at least one *rejected* output per case (a negative witness), and flag dead guards / never-satisfied law-hypotheses as STABILITY **errors**, not warnings.

**Who backs it:** Leino (the single most-repeated Dafny teaching: over-strong/vacuous specs verify trivially and prove nothing), Leroy (non-vacuity + coverage obligation; "exhibit at least one rejected output per case"), Pierce (Tyche: always-passing generator; dead guards as coverage report), O'Hearn (under-specification + exhaustiveness silently certifies a vacuously-satisfiable spec), Lamport ("exhaustive guards give totality, not adequacy"). **5 experts, sharply aligned on a concrete mechanism.**

**Why it matters:** The agent is an optimizer; a stochastic patch-search reward-hacks an under-constrained R far more aggressively than a human ever would (Leroy). The current consistency check guards one direction of vacuity and leaves the more dangerous direction (over-permissive R) entirely to human eyeballing.

### 3. Get the elaborator out of the TCB — prove statement-preservation, don't "audit once"
**What to change:** The elaborator is currently "per-spec, mechanical, statements-only" and trusted. Replace trust with a kernel-checked guarantee: emit, alongside the prover statement, a proof that the emitted statement denotes the same relation R as the signed surface spec (relational-compilation / Narcissus-derivation style). At minimum, property-test the elaborator against a reference denotational semantics of k4kspec with a round-trip (`elaborate` preserves R).

**Who backs it:** Chlipala (relational compilation: "audited once" is exactly the refuted posture; make the elaborator proof-producing so it leaves the TCB), Klein (verify the elaborator or shrink to a tiny core and prove statement-preservation, à la translation validation), Leino (Boogie history: source→IVL→SMT is where soundness bugs hide), Swamy (verify elaborator *adequacy* once, as EverParse does for its generator), Ringer (Passport: encoding choices are semantically load-bearing, ~38% outcome swing; property-test against reference semantics), Leroy (a hidden agent-chosen encoding can satisfy the statement while diverging from the human's reading). **6 experts.**

**Why it matters:** If the elaborator mistranslates one guard, the kernel cheerfully proves the wrong theorem and the engineer's signature certifies nothing. This is the one TCB component that sits *directly between* the human-signed artifact and the proof — a bug here voids both legs of trust simultaneously.

### 4. Treat the I/O shim as a reviewed refinement, not a footnote — and as an adversary across the roadmap
**What to change:** The shim is "audited once per class × prover." Instead: (a) give the shim its own observational spec statement an engineer signs, with its own EXAMPLES (Lamport: the shim *is* the spec's contact with reality); (b) state the trace property + frame condition it enforces and prove the shim enforces it (Swamy, SCIO*); (c) document the residual model/reality gap (buffering, NUL-in-path, encoding, partial reads) as *named* TCB assumptions in a per-certificate manifest.

**Who backs it:** Lamport (the shim is the model; "audited once" smuggles the model/reality gap back under a reassuring word), Klein (model↔reality boundary is where real systems break; publish a per-spec manifest naming shim/extraction/runtime/audit-date), Swamy (SCIO*: needs reference monitoring + proven secure-compilation criterion, not a one-time audit), Pierce (audit the shim as refinement in the "From C to Interaction Trees" sense; document network/OS refinement gap), Chapman (Explicit Assumptions: every tool/model-boundary assumption must be discharged or it silently voids the proof), Leroy (differential-test shim + value algebra continuously, Csmith-style — statistically where wrong-code bugs live). **6 experts.**

**Why it matters:** An under-specified shim is an unsound axiom in *every* proof above it (Swamy). "Audited once" is especially fragile because k4k lets the agent self-select toolchains, multiplying shims (see Reopened Decisions).

### 5. Empirically validate the "ordinary engineer can review k4kspec" claim — measure, don't assert
**What to change:** Run a reviewability/escaped-defect study with *non-proof-engineers*: inject wrong-but-type-correct, guard-exhaustive k4kspecs (mutation testing on real specs) and measure the escape rate among real software engineers. Publish the number. Treat readability as a hypothesis under test.

**Who backs it:** Ringer ("the single number on which the whole project's credibility rests"; mutation/escaped-defect study), Klein ("an empirical claim about human comprehension, asserted, not defended"; measured "engineer disagreed with the denotation" rejection rate), Chlipala (run an actual reviewability study before committing to "the spec is the anchor"), Pierce (two-sidedness; LAWS with nested quantifiers are where intuition fails), Leino (readability is empirical, not architectural; nested forall/exists is where readers fail), Chapman (no evidence a decision table is easier to validate against intent than the program). **6 experts.**

**Why it matters:** Leg (a) of the trust story is entirely an empirical claim about human comprehension. The LAWS sub-language (arbitrary propositions, quantifiers) is the *unreadable* part and it carries the certification. Until measured, "certified" overclaims.

### 6. Surface counterexample/diagnostic feedback into the agent loop (EFFICIENCY depends on it)
**What to change:** The harness's EFFICIENCY claim ("each context update reduces the gap") presumes the agent gets actionable signal. Pipe prover counterexample models / failure diagnostics back into agent context, and add an *incorrectness* (sound-for-bugs) cheap counterexample search that runs on every proposed patch *before* spending Tier-A proof budget.

**Who backs it:** Leino (Dafny pairs verification with a counterexample model; a stochastic agent looping against opaque reject signals won't converge), O'Hearn (Incorrectness Logic: cheap sound-for-bugs check before the heavyweight gate; the loop only chases correctness, never catches wrong-but-unconstrained behavior), Ringer (Baldur: feeding back failed attempt + error message lifts results meaningfully). **3 experts, but directly tied to k4k's own EFFICIENCY axiom.**

**Why it matters:** k4k asserts convergence as a founding thesis but the design doesn't specify the diagnostic channel that makes convergence efficient. An incorrectness pre-gate also closes O'Hearn's distinct concern: an under-specified R lets a patch be "deeply wrong on the dimensions R left free."

---

## DISAGREEMENTS

**Tension 1 — Maximal rigor (verify the elaborator/shim/extraction in-kernel) vs. testing-as-sufficient.**
Chlipala and Klein want every gap *eliminated or itself verified* (proof-producing elaborator, verified extraction, Cogent-style co-generated proofs). Leroy and Pierce are content to *differentially/property-test* the same components ("test executable forms," Csmith-style continuous testing), accepting residual risk if it's measured and statistically cornered. Lamport sits between: he wants the spectrum of formality chosen *per component* ([3], "a toolshed is not a bridge").

**How k4k's per-property tier model reconciles:** This is exactly what a per-property/per-component tier knob is for. k4k already has tiers; extend the tier dimension to the *perimeter* components, not just the implementation. A given certificate can carry: elaborator = proof-producing (Chlipala-grade) for high-assurance specs, vs. property-tested-against-reference-semantics (Leroy/Pierce-grade) for a toolshed CLI. Lamport's "let the engineer choose the blueprint's resolution per component" is the reconciling principle: make rigor a declared, per-certificate attribute rather than a global default.

**Tension 2 — New surface language (k4kspec) vs. shallow library in an existing prover.**
Chlipala (SNAPL "End of History") argues k4kspec is a *liability*: every surface form is new trusted elaboration code and new things the SWE must learn; a Gallina/Lean library of the same combinators needs *no* trusted elaborator. The rest of the panel (Lamport, Pierce, Klein) treat the observational, prover-vocabulary-free surface as k4k's *single best decision* precisely because it's readable to non-proof-engineers — which a Gallina library is not.

**How the tier model reconciles:** These optimize different variables — Chlipala minimizes TCB, the others maximize reviewability, and reviewability is k4k's whole thesis. Reconciliation: keep the readable surface (it's the certification anchor) but adopt Chlipala's *method* to discharge the cost — prototype each surface form as a shallow library first, and only *promote* it to trusted k4kspec syntax once (a) the library encoding is shown genuinely unreadable to SWEs, and (b) the elaborator's statement-preservation is proven (Convergence #3). That makes the new-language tax a per-form, evidence-gated decision rather than a blanket commitment.

**Tension 3 — Observational/functional spec is the right anchor vs. it cannot express what actually matters.**
Most of the panel praise the observational vocabulary as the best decision. Chapman dissents hardest: an observational *functional* relation R *cannot even state* secret-erasure (a proven `wipe(buf)` is deleted by dead-store elimination and is observationally invisible), constant-time, or resource bounds — the requirements that "get people killed or pwned." Lamport's adjacent dissent: the model is only safety; liveness/fairness arrive at the server tier and don't compose additively onto a relational I/O model.

**How the tier model reconciles:** Add a per-artifact **non-observable-obligations checklist** (Chapman) — secret-erasure, constant-time, resource bounds — that the engineer must *discharge or explicitly waive* per certificate, orthogonal to the functional tier. And state the behavior model as length-1 *behaviors* now (Lamport), so the temporal/liveness tier is a generalization rather than a rewrite when the roadmap hits server/UI. The tier model already treats artifact class as a plugin dimension; these are two additional, declared dimensions (non-functional obligations, behavior-length) rather than a contradiction.

---

## REOPENED DECISIONS

**TIER-A-by-default is challenged from both sides.**
- *Loosen:* Lamport ([3], formality spectrum — "do not force TIER A on every toolshed") and implicitly Leroy/Pierce (test-sufficient for low-stakes) argue default full verification is over-spec for a toolshed.
- *Tighten the meaning of "Tier A":* Klein, Chlipala, Swamy, Ringer argue that with an unverified elaborator + audited-once shim + trusted extraction, current "Tier A" *isn't actually full verification* — it's "proven modulo a large untracked perimeter." Ringer: stop saying "certified" unqualified; say "proven to satisfy a human-reviewed observational spec, modulo elaborator+shim+kernel."
- **Net:** Don't change the default mechanically, but (a) make tier a per-property/per-component choice including the perimeter, and (b) redefine what a Tier-A certificate *asserts* by publishing a per-spec TCB manifest (Klein, Chapman). The word "certified" must be qualified.

**Agent-picks-toolchain is the most broadly reopened decision.**
Swamy, Chlipala, Chapman, Klein, Leroy all attack self-selection directly. The TCB becomes the *union* of three kernels + three shims + three extraction paths (Chlipala). EverCrypt succeeded by *unifying* under one toolchain to keep the TCB auditable (Swamy); Chapman: forbid agent toolchain selection until each shim has a soundness argument. **Recommendation: pin ONE prover for v1; defer self-selection; add provers as audited plugins, not stochastic per-project choices.** This is near-unanimous and revises a current "decision already taken."

**Rocq + extraction as the canonical Tier-A path is challenged on the extraction step specifically.**
Chlipala (relational compilation: Coq's standard extraction is a *trusted, unverified soundness hole*), Klein (translation validation exists *because* we refused to trust the compiler; "extraction reintroduces exactly that gap and waves it through"), Leroy (verified extraction now exists — use it), Swamy (EverCrypt: F*→Low*→C avoids the extraction gap entirely). **Recommendation: either adopt verified extraction, switch to a Cogent/Low*-style co-generating compiler, or count extraction loudly and explicitly in every TCB manifest.** The Rocq+extraction path isn't wrong, but its extraction step must stop being silent.

---

## TOP 5 ACTIONS

1. **Build the executable-spec validation phase** (oracle + differential/adversarial/random testing of R, auto-mined counterexamples surfaced to the human). *Backing: Leroy, Pierce, Swamy, Klein, Ringer, Leino (6+).* **Effort: M.** This is the highest-leverage gap and R is already executable, so the machinery is mostly test-harness plumbing.

2. **Pin one prover for v1 and freeze agent toolchain self-selection.** *Backing: Swamy, Chlipala, Chapman, Klein, Leroy (5).* **Effort: S.** It's a decision reversal plus removing a code path — cheap and it shrinks the TCB from a union of three stacks to one auditable stack immediately.

3. **Add the anti-vacuity obligation to STABILITY** (negative witness per case; dead-guard and never-satisfied-law-hypothesis become errors). *Backing: Leino, Leroy, Pierce, O'Hearn, Lamport (5).* **Effort: S.** Mostly a static analysis over the existing decision table + a required negative EXAMPLE row.

4. **Make the elaborator statement-preserving** — emit a kernel-checked adequacy lemma (R-denotation = emitted statement), or at minimum property-test against a reference denotational semantics of k4kspec. *Backing: Chlipala, Klein, Swamy, Leino, Ringer (5).* **Effort: L.** Requires a formal denotational semantics for k4kspec; the largest item but it removes the one TCB component sitting directly between the signature and the proof.

5. **Publish a per-certificate TCB manifest + run a non-proof-engineer reviewability study, and stop saying "certified" unqualified.** *Backing (manifest): Klein, Chapman, Ringer; (study): Ringer, Klein, Chlipala, Pierce; (honest claim): Ringer.* **Effort: M** (manifest S, study M). The manifest names shim/extraction/runtime/value-algebra/elaborator + audit dates per certificate; the study measures the escaped-defect rate that the entire trust thesis silently assumes.

---

## CAVEATS

- **Rod Chapman, citation [5] (Tokeneer Experiments) — FLAGGED.** Two defects: (i) author-order misattribution (actual: Woodcock, Aydal, Chapman; cited as Chapman, Woodcock, Aydal); (ii) the paper is mischaracterized — it is a model-based-testing study finding anomalous scenarios, *not* a post-release defect analysis comparing verified vs. unverified code. **Discount the specific claim** that "of the defects found after release, the formally-verified SPARK was nearly clean — the errors lived in the unverified support code and at the spec boundary." That empirical "verified code stayed clean, bugs lived at the boundary" assertion should not be treated as established by this citation. **However**, Chapman's load-bearing recommendations do *not* depend on it: the secret-erasure / constant-time / resource-bound argument rests on [6] (Sanitizing Sensitive Data, unflagged), the explicit-assumptions/TCB argument rests on [4] (unflagged), and the pin-one-toolchain argument rests on [1][2][3] (unflagged). So Chapman's contributions to Convergence #4, the non-observable-obligations checklist, and the agent-toolchain reversal all survive; only his strongest rhetorical evidence for "the boundary, not the proof, is where bugs live" is weakened (and that same conclusion is independently supported by Leroy's CompCert/Csmith data [3][4] and Klein's seL4 account, both solid).

- **Talia Ringer, citation [3] (PUMPKIN PATCH) — minor year slip only (CPP 2018, cited 2019).** Paper, author, and topic are genuine. **No discount:** her proof-repair / spec-edit-brittleness argument and the statement-preservation recommendation stand fully.

- **All other experts: solid or minor-issues with no flags.** Lamport, Leroy, Klein, and Pierce carry the keystone consensus (proof is the easy leg; validate the spec and the perimeter) on clean citations, so the core convergence is not citation-dependent.

---

## Per-expert deep dives

### Leslie Lamport

**Citation-check:** minor-issues

**Keystone:** The proof is the easy leg; trust actually rests on the human's judgment that the spec R (and the trusted I/O shim it depends on) is the RIGHT abstraction of reality — a judgment humans are demonstrably bad at making. k4k must make R and the shim reviewable AS A MODEL OF THE WORLD, not merely short, total, well-formed, and machine-proven self-consistent.

## Review of k4k from a TLA+ / Temporal-Logic-of-Actions Perspective

### Which of my results bear on k4k

k4k's central artifact — an observational spec phrased only in the program's observable vocabulary, denoting a relation R ⊆ (Input × Output), with a correctness theorem ∀i. R i (run i) — is essentially the WHAT/HOW separation I have argued for my whole career. In *Computer Science and State Machines* I insist computation be described in mathematics, not a programming language, and that a system is a set of behaviors with implementation being logical implication [1]. *Specifying Systems* makes the same move operational: a spec describes "what the system is allowed to do," emphasizing safety properties, with TLA letting one system-implements-another reduce to ⇒ [2]. In *Who Builds a House Without Drawing Blueprints?* I argue a spec is an abstraction that "describes the important aspects and omits the unimportant ones," and that formality is a spectrum — a toolshed is not a bridge [3]. And *How to Write a 21st Century Proof* is directly the load-bearing wall under k4k's "engineer signs the spec, machine proves the impl" thesis [4].

### Strengths I recognize

The deliberate under-specification via a *relation* R rather than a function is exactly right, and most homegrown spec efforts get this wrong. Letting R be non-singleton ("stderr wording unspecified") is the abstraction discipline of [1][2]: you state only what matters and frame the rest. The FRAME+FOOTPRINT model — everything outside the declared footprint is provably unchanged — is a clean safety property in the *Proving the Correctness of Multiprocess Programs* sense [5], and getting "touches nothing else" for free is the kind of invariant that catches real design errors. The total-deterministic `run: Input→Output` semantic domain is honest: you have picked a behavior model and committed to it, which is more than most. And the agent-never-self-certifies / propose-accept-reject split correctly locates trust where [4] demands it: in mechanical checking, not in anyone's belief.

### Weaknesses I would attack

**1. "Observable behavior" hides the model, but the I/O shim *is* the model.** Your TCB includes a "trusted I/O shim, audited once per class × prover." But the whole point of [1] is that the hard part of specification is choosing the right state-machine abstraction of reality; the shim is precisely that choice. "Audited once" smuggles the model/reality gap back in under a reassuring word. The correctness theorem ∀i. R i (run i) is conditional on the shim, and an engineer signing R does not see the shim.

**2. A spec is not simple just because it is short.** k4k assumes a KISS program yields a spec "any standard software engineer can review." [4] is built on the empirical observation that *humans are bad at validating proofs they believe* — and a spec is a thing one validates by believing. Guarded CASES (a decision table) plus arbitrary-proposition LAWS is enough rope to write a R that looks plausible and is wrong. Exhaustive guards give totality, not adequacy: you can be total and specify the wrong relation. Nothing here checks that R says what the human *meant*.

**3. You have only safety, and you have hidden it.** Your domain is `run: Input→Output`, a single input/output pair — pure functional, terminating, one-shot. That is partial correctness + termination, the two things [5] generalizes. The moment the roadmap reaches "stateful ADT" and "server/daemon," you need liveness and fairness, which [2] devotes its entire second half to and which do *not* compose additively onto a relational I/O model. Deferring the temporal layer to the UI plugin understates the problem: liveness arrives at the *server* tier.

**4. STABILITY as a static check is a category error in naming.** You renamed a two-run dynamic check to a static "parses + type-checks + guards exhaustive + consistent." That is well-formedness, not stability. In TLA, stability/stuttering-invariance is a semantic property of behaviors [2]; calling syntactic well-formedness "stability" will mislead the very engineers you want to trust the artifact.

### Actionable recommendations

- **Make the shim a reviewed spec, not a footnote.** Give it its own observational statement an engineer signs, with its own examples. Per [1], the shim *is* the specification's contact with reality; it deserves the same scrutiny as R, not a one-time audit.
- **Force adequacy evidence, not just totality.** Borrow the hierarchical discipline of [4]: require the human to discharge, by hand, that named LAWS imply the EXAMPLES and that the CASES cover intended scenarios — make the reviewer prove they understand R, not merely read it.
- **State the behavior model explicitly now, before the server tier.** Adopt a TLA-style behaviors-as-sequences domain even for v1 CLI (a length-1 behavior), so the eventual liveness extension [2][5] is a generalization, not a rewrite.
- **Rename STABILITY to WELL-FORMEDNESS.** Reserve "stability" for a genuine stuttering/behavior property [2].
- **Take the formality spectrum seriously [3].** Let the engineer choose the blueprint's resolution per component; do not force TIER A on every toolshed.

### Keystone

The trust does not rest on the proof — it rests on the *spec being the right abstraction of reality*, and that judgment is made by a human who is provably unreliable at it [4]. k4k must therefore spend its design budget making R, and especially the I/O shim, *reviewable as a model of the world*, not merely short, well-formed, and machine-proven against itself.

**Citations:**

- [1] *Computer Science and State Machines* — Leslie Lamport (Festschrift / lamport.azurewebsites.net (state-machine.pdf), 2008). <https://lamport.azurewebsites.net/pubs/state-machine.pdf>  _[ok]_
- [2] *Specifying Systems: The TLA+ Language and Tools for Hardware and Software Engineers* — Leslie Lamport (Addison-Wesley, 2002). <https://www.amazon.com/Specifying-Systems-Language-Hardware-Engineers/dp/032114306X>  _[ok]_
- [3] *Who Builds a House Without Drawing Blueprints?* — Leslie Lamport (Communications of the ACM, 58(4), 2015). <https://dl.acm.org/doi/10.1145/2736348>  _[ok]_
- [4] *How to Write a 21st Century Proof* — Leslie Lamport (Journal of Fixed Point Theory and Applications / lamport.azurewebsites.net (proof.pdf), 2012). <https://lamport.azurewebsites.net/pubs/proof.pdf>  _[ok]_
- [5] *Proving the Correctness of Multiprocess Programs* — Leslie Lamport (IEEE Transactions on Software Engineering, SE-3(2), 125-143, 1977). <https://lamport.azurewebsites.net/pubs/proving.pdf>  _[ok]_

---

### Xavier Leroy

**Citation-check:** solid

**Keystone:** A machine-checked proof does not eliminate risk; it relocates all of it into the specification and the unverified perimeter around it (the value algebra, the I/O shim, the elaborator). CompCert's bugs were found exactly there, never in the proven core. Therefore k4k's human-signed observational spec must itself be made executable, adversarially/differentially tested against the engineer's intent, and proven non-vacuous (satisfiable but not trivially weak) — because if R is wrong, k4k will have flawlessly certified the wrong thing.

## Review of k4k from the CompCert perspective

k4k's central wager — a stupidly-simple program admits a simple observational spec an ordinary engineer can vouch for, and a machine-checked proof closes the rest — is structurally the CompCert wager applied to synthesis rather than compilation. I am sympathetic, but my own experience says the hard part is not where k4k has put its effort.

**Results that bear on k4k.** CompCert's correctness statement is `program_behaves (Asm.semantics tp) b -> exists b', program_behaves (Csem.semantics p) b' /\ behavior_improves b' b` [1][2]. Two things matter for k4k. First, correctness is stated over *observable behaviors* — traces of I/O events, with a refinement ("improves") relation, not equality [1][2]. k4k's `R ⊆ Input×Output` relation with deliberate under-specification is exactly the right shape; you have independently rediscovered that observational, refinement-style specs are what make verified components composable, and that a singleton `R` is the fully-determined special case. Second, and decisively, the whole guarantee is stated *relative to two formal semantics that are themselves unverified*: `Csem.semantics` is ~2500 lines, `Asm.semantics` ~400 [1]. The accompanying TCB analysis confirms the formal semantics of source and target, plus the Coq kernel, the extraction pass, and the assembler/printer, are all trusted, not proven [3].

**Strengths I recognize.** (1) Observational vocabulary (argv/stdin/env/reads ↦ stdout/stderr/exit/writes) deliberately avoids the prover vocabulary in the human-facing artifact. This is the single most important design choice and it is correct: it keeps the certification anchor in terms a domain expert can validate, closing the "model/reality gap" the way our trace-based semantics did. (2) The frame/footprint discipline giving a free "touches nothing else" property is precisely the kind of structural invariant that pays for itself — analogous to how our memory model's separation made the back-end proofs tractable. (3) "No agent self-certification; only verifier + human accept" mirrors my own discipline: the proof assistant, not the author, is the oracle.

**Weaknesses I would attack — each tied to a specific result.**

1. *The spec is in your TCB, and it is the dominant residual risk.* My ICALP 2016 talk asks the two questions that decide everything: "Does the statement of the theorem say what we think it says? Are the definitions it uses correct?" [1]. CompCert's residual bugs were found *exactly* there: Csmith found zero wrong-code bugs in the verified middle-end after six CPU-years, but did find bugs in the unverified front-end and in the assembly stage [4]. k4k's `R i (run i)` is only as good as `R`, the blessed value algebra, the I/O shim, and the elaborator. You audit the shim "once per class×prover" and call the elaborator "mechanical" — that is precisely the unverified perimeter where CompCert's real bugs lived. Your TCB claim understates this: the spec *is* the certificate, so spec-authoring risk is not a footnote, it is the whole game.

2. *Vacuity / unsatisfiability.* I demonstrate the failure mode with a deliberately wrong `ge` whose mistaken base case makes a "theorem" provable yet meaningless [1]. k4k's static "consistent (no input forced to an empty acceptable set)" check guards against the empty-`R` case, but not against an `R` that is satisfiable yet *wrong* — too weak (vacuously easy laws) or quietly mis-modeling intent. The agent, being an optimizer, will find the cheapest `run` that satisfies a weak `R`; a stochastic patch-search will reward-hack an under-constrained spec far more aggressively than a human compiler writer ever did.

3. *The agent never certifies, but it authors the proof development — including the encoding.* The danger in CompCert was definitions that "do not show up in the statement of the final theorem" [1]. A hidden prover encoding chosen by the agent can satisfy the elaborated statement while diverging from the human's reading of the surface spec. The elaborator being trusted does not protect you if the agent picks an encoding whose statement is technically what the elaborator emitted but not what the engineer signed.

**Actionable recommendations.**

- Make the spec *executable* and test it. My standing prescription is "Test executable forms of the specifications" [1]; Campbell, Blazy and Leroy built a reference interpreter animating the CompCert C semantics on real programs to catch exactly spec-level mistakes [5][6]. k4kspec should compile not only to a prover statement but to an executable oracle; run the human's EXAMPLES *and* differential/random inputs through it before any proof is attempted. Your EXAMPLES rows are a start — make them adversarial and many.
- Add an explicit *non-vacuity / coverage* obligation: prove `R` is satisfiable *and* exhibit at least one rejected output per case, so a too-weak law is visibly too weak.
- Treat the I/O shim and value algebra as you would CompCert's assembler stage: differential-test them continuously (Csmith-style) [4], because that is statistically where your wrong-code bugs will be [3][4].
- Get the extraction/runtime out of the TCB where you can: verified extraction now exists [7].

**Keystone.** A machine-checked proof shifts all residual risk into the specification and the unverified perimeter around it. k4k must therefore treat the human-signed spec as executable, adversarially tested, and provably non-vacuous — otherwise you have certified the wrong thing, beautifully.

**Citations:**

- [1] *Formally verifying a compiler: what does it mean, exactly? (ICALP 2016 invited talk slides)* — Xavier Leroy (ICALP 2016, 2016). <https://xavierleroy.org/talks/ICALP2016.pdf>  _[ok]_
- [2] *Formal verification of a realistic compiler* — Xavier Leroy (Communications of the ACM 52(7):107-115, 2009). <https://dl.acm.org/doi/10.1145/1538788.1538814>  _[ok]_
- [3] *The Trusted Computing Base of the CompCert Verified Compiler* — David Monniaux, Sylvain Boulmé (ESOP 2022 / arXiv:2201.10280, 2022). <https://arxiv.org/pdf/2201.10280>  _[ok]_
- [4] *Finding and Understanding Bugs in C Compilers (Csmith)* — Xuejun Yang, Yang Chen, Eric Eide, John Regehr (PLDI 2011, 2011). <https://users.cs.utah.edu/~regehr/papers/pldi11-preprint.pdf>  _[ok]_
- [5] *An Executable Semantics for CompCert C* — Brian Campbell (CPP 2012, LNCS 7679, 2012). <https://homepages.inf.ed.ac.uk/bcampbe2/compcert/cpp-preprint.pdf>  _[ok]_
- [6] *Mechanized semantics for the Clight subset of the C language* — Sandrine Blazy, Xavier Leroy (Journal of Automated Reasoning 43(3):263-288 / arXiv:0901.3619, 2009). <https://arxiv.org/pdf/0901.3619>  _[ok]_
- [7] *Verified Extraction from Coq to OCaml* — Yannick Forster, Matthieu Sozeau, Nicolas Tabareau, et al. (PLDI 2024 / Proc. ACM PL, 2024). <https://dl.acm.org/doi/10.1145/3656379>  _[ok]_

---

### Adam Chlipala

**Citation-check:** minor-issues

**Keystone:** The single point of trust must be the human-signed observational spec, and the only way to keep it trustworthy is to drive both the implementation AND the toolchain bridge by proof-producing refinement from that spec — so any unverified step (Coq extraction, the per-spec "mechanical" elaborator, the audited-once I/O shim) is a silent gap that can make the proof certify something other than what the engineer read. Eliminate, or itself verify, every such gap; do not merely "audit it once."

## Review of k4k from the perspective of Adam Chlipala

k4k's thesis — a simple program yields a simple spec an ordinary engineer can vouch for, plus a machine-checked proof — is exactly the wager I have spent a decade making, so I will hold it to the standards my own group failed and partly met.

**(1) What of mine bears on this.** Fiat [1] is the closest precedent: declarative specs (SQL-like set semantics) refined by automated, *proof-trail-leaving* tactics into efficient code, with the Coq kernel as the only added trust. k4k's "spec denotes a relation R over (Input × Output), correctness is ∀i, R i (run i), a singleton R means fully-determined output, non-singleton means deliberate under-specification" is precisely Fiat's nondeterministic-spec-as-set-of-acceptable-behaviors framing. The SNAPL "End of History" manifesto [2] argues the right move is *library design inside a proof assistant*, not new DSL design — directly relevant because k4k proposes a new surface language (k4kspec) plus a trusted elaborator, the very thing I argued you can usually avoid. Narcissus [3] is the cautionary jewel: it gets correctness *because* one format spec derives both decoder and encoder, eliminating the redundancy that lets two hand-written artifacts disagree. Relational compilation / Fiat-to-Facade [4] makes the sharpest point for k4k: Coq's standard extraction is *trusted*, an unverified gap between what you proved and what runs, and the cure is proof-producing compilation rather than trusting a translator. Bedrock [5] and CPDT [6] supply the engineering lessons on automation brittleness and TCB hygiene.

**(2) Strengths I recognize.** The observational spec — phrased only in argv/stdin/env/reads → stdout/stderr/exit/writes — is the correct anchor: it closes the model/reality gap at the *spec* boundary, which is exactly where Fiat specs are weakest (Fiat's SQL semantics still presume a faithful relational model). The relation-valued denotation with deliberate under-specification is more honest than a function, and the frame/footprint discipline gives you a free "touches nothing else" theorem — that is genuinely separation-logic thinking [5] applied at spec level, and it is the right instinct. Forcing authors to compose only *blessed, total, prover-realized* primitives mirrors my insistence in CPDT [6] that you build a closed, well-understood vocabulary rather than ad-hoc tactics. And "only the verifier and human judge validity; the agent never self-certifies" is the correct trust posture.

**(3) Weaknesses I would attack, each tied to a result.** *(a) The elaborator and shim are unverified gaps.* You call the elaborator "per-spec, mechanical, statements-only" and the I/O shim "audited once per class×prover." Relational compilation [4] is the direct refutation of "audited once" as sufficient: I showed extraction is a real soundness hole precisely *because* it is trusted-not-verified. Your elaborator translates the human-signed spec into the prover *statement* — if it mistranslates, the kernel cheerfully proves the wrong theorem and the engineer's signature certifies nothing. An audit is not a proof; this belongs *inside* the kernel-checked artifact via a Narcissus-style derivation, not beside it. *(b) New language vs. library.* SNAPL [2] argues k4kspec is a liability: every surface form you add is new trusted elaboration code and new things the SWE must learn, whereas a Gallina/Lean library of the same combinators would need *no* trusted elaborator at all. *(c) "Simple enough to review" is unproven and possibly false.* Narcissus [3] and Fiat [1] both found that *natural-looking* specs hide subtle obligations (exhaustiveness, inverse-ness, totality). Your static "stability" check (exhaustive guards, non-empty acceptable sets) is good, but an engineer reading a relational LAW with quantifiers is reviewing a logical proposition, not English — the "any standard software engineer, not a proof engineer" claim is the load-bearing assumption and you have no evidence for it. *(d) Toolchain self-selection is unsound across provers.* Letting the agent pick Rocq vs Frama-C/WP vs Lean means your TCB is the *union* of three kernels plus three shims; CPDT/Bedrock [5][6] teach that automation and TCB must be co-designed, not chosen per-project by a stochastic agent.

**(4) Actionable recommendations.** (i) Make the elaborator *proof-producing*: emit, alongside the prover statement, a kernel-checked lemma that the statement is the denotation of the signed surface spec — relational-compilation style [4] — so the elaborator leaves the TCB. (ii) Prototype k4kspec as a *shallow library* in one prover first [2]; only promote a surface form to k4kspec once you can show the library encoding is genuinely unreadable to SWEs. (iii) Adopt the Narcissus inverse-derivation pattern [3] for any place two artifacts must agree (e.g. spec EXAMPLES vs. denotation): *derive* one from the other, never check two hand-written things. (iv) Run an actual reviewability study with non-proof-engineers before committing to "the spec is the anchor." (v) Pin one prover for v1; defer self-selection.

**(5) Keystone** — below.

**Citations:**

- [1] *Fiat: Deductive Synthesis of Abstract Data Types in a Proof Assistant* — Benjamin Delaware, Clément Pit-Claudel, Jason Gross, Adam Chlipala (POPL 2015, 2015). <https://adam.chlipala.net/papers/FiatPOPL15/>  _[ok]_
- [2] *The End of History? Using a Proof Assistant to Replace Language Design with Library Design* — Adam Chlipala, Benjamin Delaware, Samuel Duchovni, Jason Gross, Clément Pit-Claudel, Sorawit Suriyakarn, Peng Wang, Katherine Ye (SNAPL 2017, 2017). <https://drops.dagstuhl.de/opus/volltexte/2017/7123/>  _[ok]_
- [3] *Narcissus: Correct-by-Construction Derivation of Decoders and Encoders from Binary Formats* — Benjamin Delaware, Sorawit Suriyakarn, Clément Pit-Claudel, Qianchuan Ye, Adam Chlipala (ICFP 2019, 2019). <http://adam.chlipala.net/papers/NarcissusICFP19/>  _[ok]_
- [4] *Relational Compilation (and Fiat-to-Facade: certified extraction to low-level code)* — Clément Pit-Claudel (with Adam Chlipala et al.) (MIT PhD thesis / PLV, 2022). <https://people.csail.mit.edu/cpitcla/thesis/relational-compilation.html>  _[ok]_
- [5] *Mostly-Automated Verification of Low-Level Programs in Computational Separation Logic (Bedrock)* — Adam Chlipala (PLDI 2011, 2011). <http://adam.chlipala.net/papers/BedrockPLDI11/>  _[ok]_
- [6] *Certified Programming with Dependent Types* — Adam Chlipala (MIT Press, 2013). <https://adam.chlipala.net/cpdt/cpdt.pdf>  _[ok]_

---

### K. Rustan M. Leino

**Citation-check:** minor-issues

**Keystone:** A machine-checked proof is only as trustworthy as the spec is non-trivial: an over-strong precondition or vacuously-true property verifies effortlessly while certifying nothing. k4k's STABILITY check guards exhaustiveness and non-empty acceptable sets but not the dual failure (universally-true / over-permissive R), and it delegates "is this spec meaningful?" to human reading. Following Dafny's hardest-won lesson and Clover's consistency-checking, k4k must make spec meaningfulness a mechanical obligation (anti-vacuity witnesses, round-trip code/prose reconstruction), not an article of faith.

## Review of k4k from the Dafny/auto-active-verification perspective

k4k's architecture rediscovers, with admirable independence, several invariants I have spent twenty years arguing for — and stumbles on a few I have spent the same twenty years warning about.

### Which of my results bear on k4k

The closest precedent is the Dafny line: an *auto-active* verifier where the human supplies specifications and the machine discharges proof obligations via an SMT backend, never asking the user to write proof scripts [1][3]. k4k's split — human-signed observational spec vs. hidden proof development — is exactly the auto-active stance pushed one level further: the agent, not a human, supplies the annotations and proof collateral, and only the verifier and human judge validity. Boogie [2] is the other direct ancestor: a *prover-independent intermediate verification language* onto which many source languages compile. k4k's "k4kspec surface → prover-independent semantic IR → Rocq/ACSL/Lean" two-stage elaboration is structurally a Boogie-style IVL, and the lesson of Boogie applies verbatim: the IVL's *encoding fidelity* is part of the trusted base, not a free abstraction. The framing model (FRAME + FOOTPRINT, "touches nothing else") is dynamic frames as used in Dafny's `reads`/`modifies` clauses [4][5]; declaring footprint and getting the complement framed for free is precisely the modular-reasoning payoff `modifies` buys. Finally, two recent works are almost the same proposal as k4k: "Dafny as Verification-Aware Intermediate Language for Code Generation" [6], where Dafny is hidden behind natural language and compiled to the target, and Clover [7], which reduces correctness to *consistency* among code, formal annotation, and docstring.

### Strengths I recognize

- **The hidden-proof / exposed-spec split is right.** Nothing observable is hidden from the certifier — this is the discipline that makes auto-active verification honest [1][6]. The agent proposing patches that the harness accepts or rejects mirrors the SMT-driven accept/reject loop in Dafny.
- **Observational specs (argv/stdin/env/files → stdout/stderr/exit/writes) attack the model/reality gap head-on.** In Dafny that gap lives in ghost state and the `Repr` idiom [5]; phrasing the spec only in observable vocabulary removes a whole error class.
- **Under-specification as a first-class relation R ⊆ Input × Output** is more honest than functional postconditions; "stderr wording unspecified" is a deliberate non-determinism that Dafny users fake awkwardly with weak postconditions.

### Weaknesses I would attack — each tied to a specific result

1. **The "simple spec an engineer can vouch for" leg is unguarded against vacuity.** My single most repeated teaching point is that an over-strong precondition or a vacuously-true postcondition *verifies trivially and proves nothing* [3]. k4k's STABILITY check tests exhaustive guards and "no input forced to an empty acceptable set," but it does **not** test that R is non-trivial in the other direction — an R that accepts *everything* for some input is equally useless and will sail through. Clover's entire contribution [7] is the reverse check: regenerate code from the annotation and test equivalence, regenerate the docstring and check semantic equivalence, precisely to catch trivial/incomplete specs. k4k has the human read the spec but provides no *mechanical* anti-vacuity obligation. That is the gap that sinks naive auto-active setups.

2. **"Simple enough for an engineer to vouch for" is an empirical claim, not an architectural one.** The Dafny experience [1][3] is that LAWS with nested `forall`/`exists` (which k4kspec permits as "arbitrary propositions") are exactly where readers' intuition fails. You allow arbitrary-proposition laws but only computable-boolean guards — the laws are the unreadable part, and they carry the certification.

3. **The IVL encoding is undersold in the TCB.** Boogie's history [2] shows the source→IVL→SMT translation is where soundness bugs hide. Calling the elaborator "mechanical, statements-only" does not exempt it; "Towards Trustworthy Automated Program Verifiers" exists because IVL translations themselves need validation.

4. **No notion of why a proof *fails*.** Dafny pairs verification with a debugger and counterexample model [3]. A stochastic agent looping against opaque reject signals will not converge efficiently; the harness's EFFICIENCY claim presumes diagnostic feedback the design does not yet specify.

### Actionable recommendations

- Add a **mandatory anti-vacuity obligation** à la Clover [7]: for each input class, require at least one EXAMPLE witnessing a *rejected* output, and check that R is neither empty nor universal. Make this part of STABILITY, not human eyeballing.
- **Round-trip the natural-language intent**: have a *second, independent* agent reconstruct prose from k4kspec and diff against the user's interaction file [7].
- Treat the **elaborator and value algebra as proof-validated**, not merely "audited once" — emit a per-spec proof that the elaborated statement entails the IR semantics [2].
- Surface **counterexample-style feedback** from the chosen prover back into agent context [3].

### Keystone

The certificate is only as good as the *non-triviality* of the spec the human signs: a machine-checked proof against a vacuous or over-strong specification certifies nothing, so k4k must make spec meaningfulness a *mechanical* obligation, not an act of faith in the engineer's reading [3][7].

**Citations:**

- [1] *Dafny: An Automatic Program Verifier for Functional Correctness* — K. Rustan M. Leino (LPAR-16 (Logic for Programming, Artificial Intelligence, and Reasoning), 2010). <https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/krml203.pdf>  _[ok]_
- [2] *A Polymorphic Intermediate Verification Language: Design and Logical Encoding* — K. Rustan M. Leino, Philipp Rümmer (TACAS, 2010). <http://www.philipp.ruemmer.org/publications/boogie-type-encoding.pdf>  _[ok]_
- [3] *Getting Started with Dafny: A Guide* — Jason Koenig, K. Rustan M. Leino (Microsoft Research (KRML 220) / Software Safety and Security tutorial, 2012). <https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/krml220.pdf>  _[ok]_
- [4] *Using Dafny, an Automatic Program Verifier (lecture notes)* — K. Rustan M. Leino (Marktoberdorf summer school / KRML 221, 2013). <https://leino.science/papers/krml221.pdf>  _[ok]_
- [5] *Dafny Reference Manual* — K. Rustan M. Leino, Richard L. Ford, David R. Cok (dafny.org documentation, 2024). <https://dafny.org/dafny/DafnyRef/out/DafnyRef.pdf>  _[ok]_
- [6] *Dafny as Verification-Aware Intermediate Language for Code Generation* — Yue Chen Li, Stefan Zetzsche, Siva Somayyajula (Dafny Workshop @ POPL 2025, 2025). <https://arxiv.org/pdf/2501.06283>  _[ok]_
- [7] *Clover: Closed-Loop Verifiable Code Generation* — Chuyue Sun, Ying Sheng, Oded Padon, Clark Barrett (NFM / arXiv (CloverBench, Dafny-based), 2024). <https://theory.stanford.edu/~barrett/pubs/SSP+24.pdf>  _[ok]_

---

### Gerwin Klein

**Citation-check:** solid

**Keystone:** A machine-checked proof transfers all trust onto the specification: k4k's entire claim of "certified" rests on the unproven, untestable hypothesis that a non-proof-engineer reading k4kspec correctly understands what it denotes. Klein's seL4 work shows the spec-intent gap is the residual risk that formalization cannot close — so k4k must treat validation of the spec (not just verification against it) as its central, empirically-defended engineering problem, and must publish a precise, mechanized statement of its TCB and assumptions.

## Review of k4k from the seL4 perspective

k4k's thesis — simple program ⇒ simple spec an ordinary engineer can vouch for ⇒ certified component when paired with a machine-checked proof — is exactly the bet seL4 made, scaled down. My work bears on it in four ways, and exposes four risks.

**(1) Relevant results.** seL4 proved functional correctness of an 8,700-LOC C kernel by refinement from an abstract spec through an executable spec to C, all in Isabelle/HOL [1,2]. The comprehensive account [3] is blunt about cost (≈11 py kernel-specific, ≈20 py including reusable framework) and about the headline scaling law: proof effort grows roughly with the *square* of specification size. Translation validation [4] later removed the C compiler from the TCB by proving source↔binary refinement with SMT automation for gcc -O1/-O2. Cogent [5] is the productivity counterpart: a restricted language whose certifying compiler co-generates C *and* an Isabelle shallow embedding plus a refinement proof, so engineers reason about the generated spec, not the C. The information-flow proof [6] extended guarantees to intransitive noninterference over the real C, via a proof calculus on nondeterministic state monads — and explicitly excluded covert/timing channels.

**(2) Strengths I recognize.** The observational spec — phrased only in argv/stdin/env/reads ⇒ stdout/stderr/exit/writes, never in prover vocabulary — is the single best decision here. seL4's abstract spec leaked monadic and implementation structure, which is precisely why a domain engineer cannot read it. k4k's refusal to expose prover vocabulary attacks the right gap. The relation-valued denotation with deliberate under-specification ("stderr wording unspecified") mirrors how we used nondeterminism in the abstract spec to avoid over-committing, and is more honest than pretending every byte is determined. The frame/footprint discipline gives a free "touches nothing else" property — a genuine separation result that, in our world, cost real proof engineering. And the two-leg trust story (readable spec + machine proof) is the correct decomposition. Restricting v1 to one-shot CLI with no abstract state is wise: it keeps the spec small, and small specs are the only ones that get proved [3].

**(3) Weaknesses I would attack — each tied to a result.**

- *The spec-intent gap is the whole ballgame, and k4k underweights it.* A proof says the implementation satisfies the spec; it says nothing about whether the spec is the one you meant [1,3]. k4k relocates 100% of trust onto "a standard software engineer can review k4kspec." That is an empirical claim about human comprehension, asserted, not defended. We never claimed an OS engineer could vouch for our abstract spec — and ours was reviewed by experts. Where is k4k's evidence that under-specified relations, exhaustive guards, and relational LAWS are *actually* readable to a non-proof-engineer who will sign them?
- *Square-law scaling will bite the roadmap, not v1.* CLI is fine. But pure-library → stateful-ADT → server/daemon → UI each enlarge the spec and add abstract state and traces; [3] predicts superlinear proof cost, and the temporal/concurrency layer for UI is where decades of research still struggle. The plugin claim "classes × provers compose additively in code" conflates *code* additivity with *proof* additivity — the latter is false in my experience.
- *The TCB claim is too casual.* k4k lists "prover kernel + extraction + runtime + value algebra + I/O shim + elaborator." Two problems. Extraction (Rocq→OCaml, Lean→C) is *not* verified and is a notorious trust hole — [4] exists precisely because we refused to trust the compiler; k4k's "extraction" reintroduces exactly that gap and waves it through. And the I/O shim "audited once per class×prover" is your reality interface; our hardware/DMA/timing-channel assumptions [3,6] show that the model↔reality boundary, not the proof, is where real systems break.
- *The trusted elaborator is a verifier you have not verified.* It compiles k4kspec to a prover statement. If it mistranslates, you prove a true theorem about the wrong proposition and the engineer's signature certifies nothing. "Mechanical, statements-only" is what we said about the C-to-Isabelle parser — and we still had to justify it carefully.

**(4) Actionable recommendations.**
- Make spec *validation* a first-class harness phase distinct from verification: mandatory EXAMPLES with negative cases, mutation testing of the spec against the human's intent, and a measured "an engineer disagreed with the denotation" rejection rate. Treat readability as a hypothesis to test, not assert.
- Verify the elaborator, or shrink it to a tiny core and prove *its* statement-preservation, the way translation validation [4] discharged the compiler.
- Adopt Cogent's posture [5]: prefer a restricted implementation language whose compiler *co-generates* the proof obligation, instead of trusting unverified extraction. Either verify extraction or count it loudly in the TCB.
- Publish a per-spec, machine-readable "what is proved / what is assumed" manifest (the seL4 discipline), naming the shim, extraction, runtime, and value-algebra audit date for every certificate.

**(5) Keystone.** See the keystone field: the proof only ever moves trust onto the spec; certifying that the spec is the *intended* one is the residual, irreducible risk, and k4k must defend it empirically — not assume it away.

**Citations:**

- [1] *seL4: Formal Verification of an OS Kernel* — Gerwin Klein, Kevin Elphinstone, Gernot Heiser, June Andronick, David Cock, Philip Derrin, Dhammika Elkaduwe, Kai Engelhardt, Rafal Kolanski, Michael Norrish, Thomas Sewell, Harvey Tuch, Simon Winwood (SOSP 2009, 2009). <https://trustworthy.systems/publications/papers/Klein_EHACDEEKNSTW_09.abstract>  _[ok]_
- [2] *seL4: formal verification of an operating-system kernel (CACM summary)* — Gerwin Klein et al. (Communications of the ACM, Vol. 53 No. 6, 2010). <https://cacm.acm.org/research/sel4-formal-verification-of-an-operating-system-kernel/>  _[ok]_
- [3] *Comprehensive Formal Verification of an OS Microkernel* — Gerwin Klein, June Andronick, Kevin Elphinstone, Toby Murray, Thomas Sewell, Rafal Kolanski, Gernot Heiser (ACM Transactions on Computer Systems (TOCS), 2014). <https://sel4.systems/Research/pdfs/comprehensive-formal-verification-os-microkernel.pdf>  _[ok]_
- [4] *Translation Validation for a Verified OS Kernel* — Thomas Sewell, Magnus O. Myreen, Gerwin Klein (PLDI 2013, 2013). <https://www.cl.cam.ac.uk/~mom22/pldi13.pdf>  _[ok]_
- [5] *Cogent: Verifying High-Assurance File System Implementations* — Sidney Amani, Alex Hixon, Christine Rizkallah, Peter Chubb, Liam O'Connor, Joel Beeren, Yutaka Nagashima, Japheth Lim, Thomas Sewell, Joseph Tuong, Gabriele Keller, Toby Murray, Gerwin Klein, Gernot Heiser (ASPLOS 2016, 2016). <https://dl.acm.org/doi/10.1145/2954679.2872404>  _[ok]_
- [6] *seL4: From General Purpose to a Proof of Information Flow Enforcement* — Toby Murray, Daniel Matichuk, Matthew Brassil, Peter Gammie, Timothy Bourke, Sean Seefried, Corey Lewis, Xin Gao, Gerwin Klein (IEEE Symposium on Security and Privacy (S&P) 2013, 2013). <https://trustworthy.systems/publications/nictaabstracts/Murray_MBGBSLGK_13.abstract>  _[ok]_

---

### Nikhil Swamy

**Citation-check:** minor-issues

**Keystone:** The certification is only as good as the link between the human-readable spec and human intent. A proof "R i (run i)" certifies the implementation against R, not R against what the user wanted. k4k's leg (a) — "an engineer can read and vouch for the spec" — is an unverified human-judgment step and is exactly where my own 3DGen experience shows specs go wrong; k4k must mechanize spec validation (symbolic test/oracle/differential generation from the denotation) and treat reviewer vouching as evidence, not proof, or it is shipping unjustified trust.

## Review of k4k (from Nikhil Swamy's perspective)

k4k sits squarely on the territory my group has worked for a decade: closing the gap between a human-meaningful specification and a machine-checked implementation, and — most recently — doing so with stochastic LLM agents kept honest by a trusted artifact and a verifier. I find the framing serious and the decisions mostly defensible. My critique targets where k4k's trust story is thinner than it admits.

**(1) What of my work bears on this.** The closest analogue is 3DGen [1]: AI agents translate informal input (RFCs, examples) into specifications in the trusted DSL 3D, EverParse [2,4] then mechanically produces provably correct C parsers. That is k4k's exact architecture — agent proposes, trusted DSL constrains, verifier certifies, human reviews — for one artifact class (binary formats). EverParse [2,4] is also the precedent for k4k's "spec language + trusted elaborator emitting statements, not proofs" design and its non-malleability/round-trip discipline. F* itself [3] is the precedent for observational, weakest-precondition-style specs of effectful programs (state, IO, exceptions), and Steel/SteelCore [5,6] is the precedent for the frame/footprint model k4k adopts — separation logic is precisely how you get "touches nothing else" for free. SCIO* [7] bears on the I/O shim: it is the formal treatment of what happens when verified code meets the unverified real world.

**(2) Strengths I recognize.** The observational-spec decision is correct and hard-won: phrasing the spec only in argv/stdin/env/reads -> stdout/stderr/exit/writes avoids the model/reality gap that sinks naive verification, and matches the I/O-effect view in F* [3]. Constraining authors to a closed, prover-realized value algebra mirrors why 3D [1] works — restricting the agent to "a class for which automated symbolic analysis is tractable" is the single most important lever for making LLM output verifiable. The frame+footprint model is the right primitive [5,6], and deferring directory traversal/globbing out-of-fragment is exactly the kind of honesty about tractability I'd insist on. "No agent self-certification; verifier accepts/rejects" is the discipline that made 3DGen [1] sound.

**(3) Weaknesses, each tied to a result.** First and most serious: k4k's leg (a) is unverified human judgment. In 3DGen [1] we found that in 2 cases the *human-authored* reference spec was wrong — caught only by symbolic differential testing against an external oracle (Wireshark). "An engineer can read and vouch for the spec" is precisely the step that failed for trained authors on simple formats. k4k treats readability as sufficient for trust; my experience says readability is necessary and badly insufficient. Second, the "trusted elaborator, statements-only, per-spec mechanical" claim understates the TCB. In EverParse [2,4] the generator is verified once and for all in F*; a per-spec elaborator that emits prover statements is itself a translation that can be wrong, and a buggy elaborator silently certifies the wrong theorem. Compare F*'s discipline [3]: the proof obligation is computed by a trusted WP calculus, not re-derived per program. Third, the value algebra and I/O shim are "audited once" — but SCIO* [7] shows the verified/unverified boundary needs reference monitoring and a proven secure-compilation criterion, not a one-time audit; an under-specified shim is an unsound axiom in every proof above it. Fourth, default Tier-A full verification with the *agent self-selecting* the toolchain (Rocq/Frama-C/Lean) multiplies the TCB across heterogeneous kernels and extraction paths; EverCrypt [8] succeeded by unifying everything under one toolchain (F*->Low*->C) precisely to keep the TCB auditable.

**(4) Actionable recommendations.** (a) Mechanize spec validation: from the k4kspec denotation, auto-generate positive/negative/differential tests via SMT — this is 3DTestGen [1] — and require the reviewer to adjudicate generated witnesses, not just read prose. Make EXAMPLES adversarially mined, not author-chosen. (b) Verify the elaborator's *adequacy* once (a proof that the emitted prover statement denotes the same relation R as the surface spec), as EverParse does for its generator [2,4]; do not trust a per-spec mechanical translation. (c) Treat the I/O shim with SCIO*-grade rigor [7]: state the trace property and frame condition it enforces and prove the shim enforces it, per class x prover. (d) Reconsider agent-selected provers; pin one Tier-A toolchain first (EverCrypt's lesson [8]) and add provers as audited plugins, not agent choices. (e) Adopt WP/Dijkstra-monad framing [3] so under-specification (a relation, not a function) composes cleanly.

**(5) Keystone.** A proof of `forall i. R i (run i)` certifies the *implementation against R* — never R against intent. k4k's entire trust claim rests on a human reading R, and that is the exact step that failed in my own LLM-assisted verified-parser work [1]. Mechanize spec-to-intent validation, or k4k ships proofs about the wrong proposition.

**Citations:**

- [1] *3DGen: AI-Assisted Generation of Provably Correct Binary Format Parsers* — Sarah Fakhoury, Markus Kuppe, Shuvendu K. Lahiri, Tahina Ramananandro, Nikhil Swamy (arXiv (cs.SE), 2024). <https://arxiv.org/abs/2404.10362>  _[ok]_
- [2] *EverParse: Hardening critical attack surfaces with formally proven message parsers* — Microsoft Research (Tahina Ramananandro, Nikhil Swamy, et al.) (Microsoft Research blog / USENIX Security, 2019). <https://www.microsoft.com/en-us/research/blog/everparse-hardening-critical-attack-surfaces-with-formally-proven-message-parsers/>  _[ok]_
- [3] *Dependent Types and Multi-Monadic Effects in F** — Nikhil Swamy, Catalin Hritcu, Chantal Keller, Aseem Rastogi, Antoine Delignat-Lavaud, et al. (POPL '16, 2016). <https://www.microsoft.com/en-us/research/publication/dependent-types-multi-monadic-effects-f/>  _[ok]_
- [4] *Hardening Attack Surfaces with Formally Proven Binary Format Parsers (EverParse3D / 3D)* — Nikhil Swamy, Tahina Ramananandro, Aseem Rastogi, Irina Spiridonova, Haobin Ni, et al. (PLDI 2022, 2022). <https://fstar-lang.org/papers/EverParse3D.pdf>  _[ok]_
- [5] *Steel: Proof-oriented Programming in a Dependently Typed Concurrent Separation Logic* — Aymeric Fromherz, Aseem Rastogi, Nikhil Swamy, Sydney Gibson, Guido Martinez, Denis Merigoux, Tahina Ramananandro (ICFP 2021 / PACMPL, 2021). <https://fstar-lang.org/papers/steel/>  _[ok]_
- [6] *SteelCore: An Extensible Concurrent Separation Logic for Effectful Dependently Typed Programs* — Nikhil Swamy, Aseem Rastogi, Aymeric Fromherz, Denis Merigoux, Danel Ahman, Guido Martinez (ICFP 2020 / PACMPL, 2020). <https://arxiv.org/abs/2111.15149>  _[ok]_
- [7] *Securing Verified IO Programs Against Unverified Code in F* (SCIO*)* — Cezar-Constantin Andrici, Stefan Ciobaca, Catalin Hritcu, Guido Martinez, Exequiel Rivas, Eric Tanter, Theo Winterhalter (POPL 2024, 2024). <https://arxiv.org/abs/2303.01350>  _[ok]_
- [8] *EverCrypt: A Fast, Verified, Cross-Platform Cryptographic Provider* — Jonathan Protzenko, Bryan Parno, Aymeric Fromherz, Chris Hawblitzel, ..., Nikhil Swamy, et al. (IEEE S&P 2020, 2020). <https://www.semanticscholar.org/paper/EverCrypt:-A-Fast,-Verified,-Cross-Platform-Protzenko-Parno/eb6f31b212e36d090a434491c013057181aafc4a>  _[ok]_

---

### Peter W. O'Hearn

**Citation-check:** minor-issues

**Keystone:** The hard part of scaling formal reasoning is not the proof, it is the human-and-workflow loop around it. Facebook deployment showed the *same* analysis getting 0% fixes in batch and ~70% at diff time [4][5]: impact is governed by when and where feedback meets the developer. k4k's trust rests on a human signing a readable spec, yet the harness invests in the prover gate and treats spec-review as an afterthought. Make spec authoring/review continuous and diff-time-local, and add a sound-for-bugs incorrectness check [6] so the under-specified relation R cannot silently certify wrong-but-unconstrained behavior. Otherwise k4k will produce proofs no one trusts, against specs no one truly read.

## Review of k4k from a separation-logic / scalable-reasoning perspective

k4k is an ambitious harness, and I read it sympathetically: it shares my long-standing conviction that the way to make formal reasoning matter is to engineer the *interface* between humans, tools, and code, not merely to invent new logics. But several of its load-bearing decisions sit in tension with what my own work taught me, and I will be blunt about where.

**(1) Results that bear on k4k.** The footprint/frame model is the part I most recognize. The principle of local reasoning — "to understand how a program works, it should be possible for reasoning and specification to concentrate on the portion of memory used by a program component, and not the entire global state" — and the frame rule that realizes it are exactly what k4k's "FRAME + FOOTPRINT" buys: a free *touches-nothing-else* property [1][2]. That is a genuinely good instinct. My compositional shape analysis via *bi-abduction* [3] is also directly relevant: it shows that the frame and the *anti-frame* (the missing precondition) can be *inferred*, per-procedure, independent of callers — which is precisely the modularity k4k will need when it climbs its roadmap from one-shot CLI to libraries, ADTs, and servers. Finally, *Continuous Reasoning* [4] and the Facebook deployment paper [5] bear on k4k's entire theory of change: they are about scaling the *impact* of reasoning through workflow, not about the strength of a single proof.

**(2) Strengths I would recognize.** First, observational specs in the program's own vocabulary (argv/stdin/env/reads ⇒ stdout/stderr/exit/writes) deliberately avoid the model/reality gap — this is the right framing-discipline, and the I/O shim audited "once per class × prover" is the honest place to localize the trust. Second, the relational denotation R ⊆ Input×Output with deliberate under-specification is well-judged: a singleton R is over-constraining, and most real correctness lives between "fully determined" and "anything goes." Third, separating the human-signed readable spec from the hidden proof development, with *nothing observable hidden*, is the correct trust boundary.

**(3) Weaknesses tied to specific results.** *The harness only chases correctness; bugs are the other side of the coin.* My Incorrectness Logic [6] exists because programmers spend most of their time reasoning about *what goes wrong*, and over-approximate Hoare reasoning is the wrong tool for that. k4k's gap-closing loop (D vs S, accept/reject) is purely correctness-shaped. A patch that passes the verifier against an *under-specified* R can be deeply wrong on the dimensions R left free; k4k has no under-approximate, no-false-positive bug-finding leg to catch that. The reviewable spec is your only firewall here, and it is thin.

*The fix-rate lesson is being ignored at the wrong layer.* The single most important empirical finding from deployment [5] is stark: the same analysis, same false-positive rate, got a **0% fix rate in batch mode and ~70% at diff time**. k4k bets everything on a heavyweight Tier-A proof gate; but if the *human's* spec-review step is slow, batched, or context-switched away from the diff, the certification anchor — leg (a) of your trust — rots, regardless of how sound leg (b) is. You have engineered the prover loop and under-engineered the human loop.

*Compositionality is deferred but is the real scaling wall.* Bi-abduction [3] scaled to millions of LOC *only* because procedure summaries compose without whole-program context. k4k's v1 is one-shot CLI with no abstract state; the moment you reach the "stateful ADT" and "server/daemon" classes, you need composable, frame-respecting summaries, and "additive composition of classes × provers in code" is not the same thing as *semantic* compositionality of specs.

*Totality-by-exhaustive-guards can mask the interesting failures.* Forcing guards exhaustive to get totality is clean, but the "no input forced to an empty acceptable set" check guarantees a relation exists, not that it is the *intended* one. Under-specification + exhaustiveness can silently certify a vacuously-satisfiable spec.

**(4) Actionable recommendations.** (i) Add an *incorrectness* tier: cheap, sound-for-bugs counterexample search [6] that runs on every proposed patch *before* the Tier-A gate, so the harness never spends a proof budget on a patch with a witnessed bad observation. (ii) Make spec review *diff-time*: surface the readable-spec delta inline with the human's editing context, measure fix/sign-off rates, and treat a slow human-review loop as a first-class harness failure [4][5]. (iii) Specify the *anti-frame* explicitly per spec and infer/check it [3], so the footprint isn't only what you write but what you provably *need*. (iv) Track false-negative risk of under-specification: report, per spec, which observable dimensions R leaves free, and require the human to sign that list, not just the cases.

**(5) Keystone.** See below.

**Citations:**

- [1] *Local Reasoning about Programs that Alter Data Structures* — Peter W. O'Hearn, John C. Reynolds, Hongseok Yang (CSL 2001 (Computer Science Logic), 2001). <http://www0.cs.ucl.ac.uk/staff/p.ohearn/onlinepapers.html>  _[ok]_
- [2] *Separation Logic (retrospective)* — Peter W. O'Hearn (Communications of the ACM, 62(2), 2019). <https://cacm.acm.org/magazines/2019/2/234356-separation-logic/fulltext>  _[ok]_
- [3] *Compositional Shape Analysis by Means of Bi-Abduction* — Cristiano Calcagno, Dino Distefano, Peter W. O'Hearn, Hongseok Yang (POPL 2009; Journal of the ACM 58(6) 2011, 2009). <https://dl.acm.org/doi/10.1145/2049697.2049700>  _[ok]_
- [4] *Continuous Reasoning: Scaling the impact of formal methods* — Peter W. O'Hearn (LICS 2018 (33rd ACM/IEEE Symposium on Logic in Computer Science), pp. 13-25, 2018). <https://dl.acm.org/doi/abs/10.1145/3209108.3209109>  _[ok]_
- [5] *Scaling Static Analyses at Facebook* — Dino Distefano, Manuel Fahndrich, Francesco Logozzo, Peter W. O'Hearn (Communications of the ACM, 62(8), 2019). <https://cseweb.ucsd.edu/~dstefan/cse227-spring20/papers/distefano:scaling.pdf>  _[ok]_
- [6] *Incorrectness Logic* — Peter W. O'Hearn (Proceedings of the ACM on Programming Languages (POPL), Vol. 4, 2019). <https://dl.acm.org/doi/10.1145/3371078>  _[ok]_

---

### Benjamin C. Pierce

**Citation-check:** solid

**Keystone:** A machine-checked proof certifies only that the implementation satisfies *the spec you wrote*, not the spec you *meant*; k4k's entire trust argument therefore rests on validating the human-signed observational spec itself — so k4k must treat the spec as software-under-test, with executability, mutation/agreement-style adequacy, and distribution-aware example generation as first-class, non-optional harness mechanisms — not on the proof, which is the easy leg.

## Reviewing k4k from the DeepSpec / QuickChick perspective

k4k's thesis — a KISS program yields a simple observational spec an ordinary engineer can vouch for, which together with a machine-checked proof yields a certified component — sits squarely inside the research program I have spent fifteen years on. Much of it I would applaud; the part it underweights is precisely the part my own work kept stubbing its toe on.

**What bears directly.** The "deep specification" position paper [1] argues for specs that are *rich, two-sided, formal, and live*. k4k's observational spec is formal and live (elaborated to a prover, proven against the implementation). But [1] is emphatic that "specifications are just another kind of software, so they are also prone to programmer mistakes," and that the load-bearing defense is *two-sidedness*: a spec validated by both implementer and client. QuickChick and the Foundational PBT framework [2] exist because we learned that executable specs are wrong constantly, and that you must *test the spec before you trust the proof*. "Property-Based Testing in Practice" [3], our 30-interview study at Jane Street, found the two dominant pain points are (i) writing properties/generators and (ii) "the difficulty of assessing whether properties are correct and meaningful." Tyche [4] was built because testers cannot tell whether a generator ever produces interesting inputs — vacuous tests pass loudly. "From C to Interaction Trees" [5] is the cleanest precedent for k4k's I/O shim: an observational spec of a networked server connected to real C, where the OS is *axiomatized*, and the model/reality gap is named explicitly as "network refinement."

**Strengths I recognize.** The observational vocabulary (argv/stdin/env/reads → stdout/stderr/exit/writes) is exactly right and matches [5]: phrasing the spec in observables, never prover terms, is the single best decision for avoiding the model/reality gap and for two-sided readability. The relation R ⊆ Input×Output with deliberate under-specification ("stderr wording unspecified") is more honest than most functional specs — it admits non-determinism in the *spec* rather than forcing false precision. The frame/footprint discipline giving a free "touches nothing else" theorem is excellent; it is the kind of cross-cutting property [1] calls for and that hand-written specs almost always forget. Requiring guards to be exhaustive computable booleans buys you totality, which is what makes the spec *executable* — and executability is the precondition for everything I'd recommend below.

**Weaknesses I would attack, each tied to a result.**

1. *The proof is the easy leg; you are guarding the wrong door.* k4k's trust rests on "(a) spec simple enough to vouch for, (b) implementation machine-proven." But [1] and [3] both show (a) is where the bugs live. k4k's STABILITY check (parses, type-checks, guards exhaustive, examples agree, in-fragment) is a *well-formedness* check, not a *validity* check. A spec can be exhaustive, consistent, and totally wrong. You have no analogue of two-sidedness: there is one writer and one reader of the spec, and no independent client.

2. *EXAMPLES are statically checked against the denotation, but who checks the denotation?* In [2] the whole point is proving the *checker* tests the intended *proposition*. k4k checks examples ⊆ R, but if R is wrong, agreeing examples are confirmation bias. Worse, examples are author-supplied — [4] shows humans systematically miss the input regions that matter (empty argv, NUL bytes, missing files, partial reads).

3. *Singleton-R as "fully determined" hides the vacuity risk.* A LAW that is trivially true (e.g., a guard that no input satisfies) is the formal-methods version of the always-passing generator [4]. Nothing in STABILITY flags a CASE whose guard is unreachable, or a LAW whose hypothesis is never satisfiable.

4. *Closed blessed value algebra is a strength for the prover and a liability for adequacy.* It bounds the TCB nicely, but [3] found generator/property authoring is the adoption bottleneck; a closed algebra means the engineer cannot express the very corner-case predicate that would catch the bug.

**Actionable recommendations.**

- Make the spec *testable against an independent oracle*, not just self-consistent. Since R is executable, run QuickChick-style PBT [2] *on the spec*: generate inputs, and for fully-determined cases differentially test R against the extracted implementation — disagreement localizes spec-or-code faults early, exactly the "low-cost bug finding" of [1].
- Add **mutation adequacy for the spec**: perturb each guard/law and require some auto-generated example to flip. This is the operational form of "is this spec vacuous?" and directly answers the [3] effectiveness gap.
- Ship a Tyche-style **coverage/distribution report** [4]: for each CASE, show how many generated inputs reach it; flag dead guards and never-satisfied law hypotheses as STABILITY *errors*, not warnings.
- Engineer **two-sidedness** [1]: have the agent generate an independent *client* against the spec; if the client cannot use the spec to do something useful, the spec is under-specified. The human signs the spec *plus* a coverage/mutation report, not the spec alone.
- Audit the I/O shim as a *refinement* in the sense of [5], and document the residual model/reality gap (buffering, NUL-in-path, encoding) as named TCB assumptions.

**Citations:**

- [1] *Position paper: the science of deep specification* — Andrew W. Appel, Lennart Beringer, Adam Chlipala, Benjamin C. Pierce, Zhong Shao, Stephanie Weirich, Steve Zdancewic (Philosophical Transactions of the Royal Society A, 2017). <https://pmc.ncbi.nlm.nih.gov/articles/PMC5597730/>  _[ok]_
- [2] *Foundational Property-Based Testing* — Zoe Paraskevopoulou, Cătălin Hriţcu, Maxime Dénès, Leonidas Lampropoulos, Benjamin C. Pierce (ITP 2015, LNCS 9236, 2015). <https://link.springer.com/chapter/10.1007/978-3-319-22102-1_22>  _[ok]_
- [3] *Property-Based Testing in Practice* — Harrison Goldstein, Joseph W. Cutler, Daniel Dickstein, Benjamin C. Pierce, Andrew Head (ICSE 2024, 2024). <https://dl.acm.org/doi/10.1145/3597503.3639581>  _[ok]_
- [4] *Tyche: Making Sense of Property-Based Testing Effectiveness* — Harrison Goldstein, Jeffrey Tao, Zac Hatfield-Dodds, Benjamin C. Pierce, Andrew Head (UIST 2024, 2024). <https://harrisongoldste.in/papers/uist24-tyche.pdf>  _[ok]_
- [5] *From C to Interaction Trees: Specifying, Verifying, and Testing a Networked Server* — Nicolas Koh, Yao Li, Yishuai Li, Li-yao Xia, Lennart Beringer, Wolf Honoré, William Mansky, Benjamin C. Pierce, Steve Zdancewic (CPP 2019, 2019). <https://arxiv.org/abs/1811.11911>  _[ok]_

---

### Rod Chapman

**Citation-check:** minor-issues — flags: [5] misattribution: author order is incorrect (actual order Woodcock, Aydal, Chapman; cited as Chapman, Woodcock, Aydal) AND the attached claim mischaracterizes the paper's content - it is a model-based-testing study finding anomalous scenarios, not a post-release defect analysis of verified vs. unverified code.

**Keystone:** Your trust rests on a human signing the spec, but the hard, well-documented industrial failure mode is the spec (and the tool/shim boundary) being wrong-but-provable. An observational, functional-only spec cannot even express the non-functional requirements (secret erasure, constant time, resource bounds) that actually decide whether a "certified" component is safe — so until k4k makes spec-validation-against-intent measurable and pins/audits a single sound toolchain, it certifies "the code satisfies R," not "the component is fit for its real purpose."

## Review of k4k from Rod Chapman's perspective

**Relevant work.** k4k's thesis — a stupidly-simple program yields a spec an ordinary engineer can vouch for, which together with a machine-checked proof gives a certified component — sits squarely on top of two decades of SPARK industrialisation I have lived through. The most directly bearing result is *Co-Developing Programs and Their Proof of Correctness* (Chapman, Dross, Matthews, Moy, CACM 2024) [1], whose whole argument is that code and proof must evolve together via auto-active verification readable by working engineers, not proof specialists — exactly k4k's "standard SWE, not proof engineer" claim. *Are We There Yet? 20 Years of Industrial Theorem Proving with SPARK* (Chapman & Schanda, ITP 2014) [2] is the hard-won retrospective on what actually breaks. *SPARKNaCl* [3] is my own running experiment in keeping an automatic proof alive across code and tool changes. The *Tokeneer Experiments* [5] and *Sanitizing Sensitive Data* [6] supply the cautionary tales. *Explicit Assumptions* [4] bears directly on k4k's TCB and shim claims.

**Strengths I recognise.** First, the insistence that *only the verifier and the human judge validity; the agent never self-certifies* is correct and non-negotiable — it is the same discipline that let SPARKNaCl's type-safety proof survive years of refactoring with zero human trust in the optimiser [3]. Second, the observational semantic domain (argv/stdin/env/reads to stdout/stderr/exit/writes) and the frame+footprint "touches nothing else" property are genuinely good engineering: a free, machine-checked frame condition is more than most certified CLI tools ship. Third, deliberate under-specification via a relation R (singleton only when you want determinism) matches how real specs work — Tokeneer left plenty unconstrained on purpose [5]. Fourth, deferring globbing/traversal out of the v1 fragment against a "spec-simplicity budget" is the right instinct: SPARKNaCl stays provable precisely because its data shapes are bounded and total.

**Weaknesses I would attack.** (1) *The certification anchor is the spec, and a wrong-but-provable spec is the most dangerous artifact you can build.* "Are We There Yet" [2] is blunt that the residual risk in industrial proof migrates almost entirely into the specification and the tool's soundness, not the code. k4k's "an engineer reads and signs it" leg is doing all the certification work, yet the brief offers no evidence that a k4kspec decision table is actually easier to validate against *intent* than the program. The Tokeneer post-mortem [5] is decisive here: of the defects found after release, the formally-verified SPARK was nearly clean — the errors lived in the unverified support code and at the spec boundary. Your boundary is the I/O shim.

(2) *Observational specs systematically miss the requirements that get people killed or pwned.* My *Sanitizing Sensitive Data* work [6] exists because erasing a secret is functionally invisible — a perfectly correct, even proven, `wipe(buf)` is silently deleted by dead-store elimination, and your observational vocabulary (stdout/exit/writes) cannot even *state* the requirement. Constant-time behaviour (central to SPARKNaCl [3]) is likewise unobservable in your model. So "certified component" overclaims: k4k certifies a *functional* relation R, not security.

(3) *The TCB is bigger than claimed.* Per *Explicit Assumptions* [4], every assumption at a tool/model boundary must be made explicit and discharged, or it silently voids the proof. k4k's TCB ("audited once") includes a per-class×per-prover I/O shim and a blessed value algebra — but you let the *agent self-select the toolchain* (Rocq/Frama-C/Lean). That multiplies shims and provers without a soundness story, contradicting the "audited once" framing.

(4) *Automation has a soundness floor.* SPARKNaCl is fully auto-active [3], but "Are We There Yet" [2] documents false VCs and the need for sound counter-examples (Riposte) precisely because provers and encodings have bugs. A stochastic agent retrying against a prover until green is an adversarial search for the prover's blind spots.

**Recommendations.** (a) Treat the elaborator and shim as airborne software: pin one prover for v1, audit one shim, and forbid agent toolchain selection until each shim has a soundness argument. (b) Add a mandatory *non-observable obligations* checklist per artifact class — secret-erasure, constant-time, resource bounds — that the engineer must either discharge or explicitly waive, à la [6]. (c) Make spec review measurable: require human-authored EXAMPLES and adversarial counter-examples the spec must reject, so the signer validates intent, not syntax [2]. (d) Adopt explicit-assumption ledgers [4] so every "framed/unchanged/audited-once" claim is a discharged obligation, not prose.

**Keystone.** The keystone below.

**Citations:**

- [1] *Co-Developing Programs and Their Proof of Correctness* — Roderick Chapman, Claire Dross, Stuart Matthews, Yannick Moy (Communications of the ACM, 2024). <https://dl.acm.org/doi/10.1145/3624728>  _[ok]_
- [2] *Are We There Yet? 20 Years of Industrial Theorem Proving with SPARK* — Roderick Chapman, Florian Schanda (Interactive Theorem Proving (ITP) 2014, 2014). <https://proteancode.com/keynote.pdf>  _[ok]_
- [3] *SPARKNaCl: SPARK 2014 re-implementation of the TweetNaCl crypto library* — Roderick Chapman (GitHub / FOSDEM 2022, 2020-2022). <https://github.com/rod-chapman/SPARKNaCl/blob/master/README.md>  _[ok]_
- [4] *Explicit Assumptions - A Prenup for Marrying Static and Dynamic Program Verification* — Johannes Kanig, Roderick Chapman, Cyrille Comar, Jerome Guitton, Yannick Moy, Emyr Rees (TAP @ STAF 2014, 2014). <https://dblp.org/pid/72/613.html>  _[ok]_
- [5] *The Tokeneer Experiments* — Roderick Chapman, Jim Woodcock, Emine Gokce Aydal (Reflections on the Work of C. A. R. Hoare (Springer), 2010). <https://link.springer.com/chapter/10.1007/978-1-84882-912-1_17>  _[UNVERIFIED/WEAK]_
- [6] *Sanitizing Sensitive Data: How to Get It Right (or at Least Less Wrong...)* — Roderick Chapman (Ada-Europe 2017 (Springer LNCS), 2017). <https://link.springer.com/chapter/10.1007/978-3-319-60588-3_3>  _[ok]_

---

### Talia Ringer

**Citation-check:** minor-issues — flags: [3] venue slip (not a hallucination): 'Adapting Proof Automation to Adapt Proofs' (PUMPKIN PATCH) is cited as CPP 2019 but was published at CPP 2018. Paper, author, and topic are all genuine; only the year is wrong.

**Keystone:** A machine-checked proof certifies only "implementation satisfies THIS spec" — so k4k's entire trust claim collapses onto whether a non-proof-engineer can actually recognize a wrong-but-type-correct k4kspec. That spec-review burden, not the proving, is the hard problem, and it must be empirically validated (mutation/escaped-defect studies on real engineers), because both the spec and the trusted elaborator/shim are unproven artifacts that silently bound every guarantee.

## Review of k4k from Talia Ringer's perspective

k4k's founding bet — that a stochastic agent converges under a deterministic, efficient, complete harness with a verifier as the sole judge of validity — is essentially the Baldur architecture generalized to whole programs [1]. In Baldur, an LLM generates whole Isabelle/HOL proofs, the proof assistant is the oracle, and feeding back a *failed attempt plus its error message* (repair) lifts results meaningfully (whole-proof generation alone ~41%; +8.7% over Thor; 65.7% combined) [1]. k4k's PROPOSE/accept-reject loop with verifier-derived state S is exactly this generate-check-repair pattern at the artifact level, so my own work strongly endorses the *shape* of the harness. I would recognize three genuine strengths immediately.

**Strengths.** First, the verifier-as-sole-judge / agent-never-self-certifies rule is precisely the lesson of Baldur: LLMs reliably emit plausible-but-wrong proofs, and only the kernel separates signal from hallucination [1]. k4k makes that non-negotiable. Second, keeping proofs/tactics/extraction *hidden* while exposing only an observational spec is the right trust factoring — it matches my long-standing position in QED at Large that proof *artifacts* are engineering byproducts, while the statement is the thing humans must own [5]. Third, framing the deliverable as *change-aware* (git accept/reject, neg-cache, splice-on-failure) resonates with proof repair: maintenance, not first-proof, is where verified software actually dies [3].

**Weaknesses, each tied to a specific result.**

1. *The spec is the unverified link, and you have not measured whether engineers can vouch for it.* A proof certifies only `forall i, R i (run i)` for the **stated** R. Baldur's guarantees, like all proof-assistant guarantees, are relative to a theorem nobody verified [1]; my whole research program exists because the spec/intent gap is the dominant failure mode, not the proof [5]. k4k's thesis B-leg ("an SWE reads k4kspec and vouches") is an *empirical* claim about human review fidelity that the brief simply asserts. I would demand a mutation study: inject wrong-but-type-correct, guard-exhaustive specs and measure escape rates among real software engineers (not proof engineers). Without that number, "certified" is marketing.

2. *Exhaustive computable guards do not equal correct case analysis — and edge cases are exactly where things break.* Our structural-recursion result shows learners fit shortcut heuristics that pass typical inputs and fail systematically on under-represented edge cases [2]. The agent authoring k4kspec is such a learner. A decision table can be totalizing (guards cover the input space) yet semantically wrong on the rare branch; STABILITY's static checks (parse/type/exhaustive/examples-agree) catch none of this. The EXAMPLES mechanism is a sparse test oracle, and sparse oracles are precisely what miss the long tail [2].

3. *Brittleness moves, it doesn't vanish.* PUMPKIN PATCH exists because a definition change shatters downstream proofs [3]. k4k hides the proof, so when the human edits the signed spec, the hidden Rocq/ACSL development must be re-proven from scratch by the agent — re-incurring the full convergence cost on every spec edit. The brief has no proof-repair/transport story; you have re-created the maintenance wall my thesis was written to remove [3].

4. *The TCB is larger and less audited than claimed.* "Elaborator (mechanical, statements-only)" + "I/O shim (audited once per class×prover)" + "blessed value algebra" are unproven trusted code. A statements-only elaborator that mistranslates one guard yields a vacuously-true or wrong theorem the kernel happily certifies. Passport showed that *which identifiers/structure you feed the encoder* changes outcomes by ~38% [4] — translation/encoding choices are semantically load-bearing, not clerical.

**Actionable recommendations.**
- **Verify, or at least property-test, the elaborator** against a reference denotational semantics of k4kspec (round-trip: `elaborate` preserves `R`). A statements-only elaborator is itself a perfect proof-repair target — apply transport (PUMPKIN Pi-style) [3] so spec edits *repair* the hidden proof instead of triggering full re-synthesis.
- **Differential spec review.** Borrow Baldur's repair signal [1]: when the agent proposes a spec, also auto-generate adversarial counter-examples *outside* the EXAMPLES set and surface disagreements to the human reviewer, directly attacking the edge-case blind spot [2].
- **Publish an escaped-defect benchmark** for non-proof-engineer spec review (mutation testing on k4kspecs). This is the single number on which the whole project's credibility rests [5].
- **Treat the I/O shim as an adversary.** Audit-once is insufficient across the CLI→ADT→server roadmap; the temporal/concurrency layer you defer is where observational specs stop being a faithful relation.
- **Stop saying "certified" unqualified.** Say "implementation proven to satisfy a human-reviewed observational spec, modulo elaborator+shim+kernel." Honesty here is the whole value proposition.

In short: k4k correctly automates the part my field already knows how to delegate to a machine (the proof) and stakes everything on the part my field has shown is hardest and most human (the spec) [3][5]. That is a defensible bet only if the spec-review fidelity is *measured*, not assumed.

**Citations:**

- [1] *Baldur: Whole-Proof Generation and Repair with Large Language Models* — Emily First, Markus N. Rabe, Talia Ringer, Yuriy Brun (ESEC/FSE 2023, 2023). <https://arxiv.org/abs/2303.04910>  _[ok]_
- [2] *Transformer-Based Models Are Not Yet Perfect At Learning to Emulate Structural Recursion* — Dylan Zhang, Curt Tigges, Zory Zhang, Stella Biderman, Maxim Raginsky, Talia Ringer (Transactions on Machine Learning Research (TMLR), 2024). <https://arxiv.org/abs/2401.12947>  _[ok]_
- [3] *Proof Repair (PhD thesis) / Adapting Proof Automation to Adapt Proofs (PUMPKIN PATCH) and Proof Repair across Type Equivalences* — Talia Ringer (University of Washington PhD thesis 2021; CPP 2019; PLDI 2021, 2021). <https://dependenttyp.es/pdf/repair.pdf>  _[ok]_
- [4] *Passport: Improving Automated Formal Verification Using Identifiers* — Alex Sanchez-Stern, Emily First, Timothy Zhou, Zhanna Kaufman, Yuriy Brun, Talia Ringer (ACM TOPLAS, 2023). <https://people.cs.umass.edu/~brun/pubs/pubs/Sanchez-Stern23toplas.pdf>  _[ok]_
- [5] *QED at Large: A Survey of Engineering of Formally Verified Software* — Talia Ringer, Karl Palmskog, Ilya Sergey, Milos Gligoric, Zachary Tatlock (Foundations and Trends in Programming Languages, 2019). <https://arxiv.org/pdf/2003.06458>  _[ok]_

---

