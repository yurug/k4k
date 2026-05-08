---
id: spec.api-contracts
type: spec
summary: Interfaces k4k depends on — agent backend (wire protocol, ADR-009), verifier (wire protocol, ADR-008), plus the public CLI contract.
domain: spec
last-updated: 2026-05-03
depends-on: [glossary, spec.data-model, spec.algorithms]
refines: []
related: [external.backend-protocol, external.verifier-protocol, external.ollama, architecture.overview]
---

# API Contracts

## One-liner

The interfaces between k4k and the outside world: the public CLI it exposes, the agent-backend interface it consumes, the verifier interface it consumes.

## Scope

Signatures, pre/post-conditions, error contracts. Implementations live in code; runtime behavior of specific backends and verifiers lives in `external/`.

## Public CLI contract

`k4k <file.k4k>`

| Form               | Pre-conditions                          | Post-conditions                                                                                                                       | Exit codes                  |
|--------------------|-----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|
| `k4k <file.k4k>`   | File exists, ≤ 10 MB, UTF-8, parseable  | The watcher process starts and runs autonomously (per `domain/prd.md`). All further interaction goes through the `.k4k` file via cotype. The process exits only on signal, terminal failure, or operator request. | 0 on graceful shutdown; non-zero only if the watcher cannot start (cotype not installed, file unreadable, host environment broken). |

That is the entire user-facing CLI surface in v2. The agent's *work outcomes* (stability verdicts, version completion, trade-off proposals, errors) are reported in the `.k4k` file, not via exit codes or stdout.

### Operator flags (NOT part of the user UX)

`-v` / `-vv` are accepted by `bin/main.ml` for *operator* debugging (helping someone develop or fix k4k itself; routing engine-level diagnostics to stderr). They do not change behavior the end user observes through the file. Documented separately from the public contract.

### Stdout/stderr discipline (`P.stdout-discipline`)

- **stdout**: structured progress events as JSONL. One line per state transition (matches what's written to `.k4k/log.jsonl`). The watcher emits these continuously; users typically don't read them. They exist for operators piping the watcher into a log aggregator.
- **stderr**: free-form diagnostics at `-v` / `-vv`; nothing at default verbosity.
- Never mix machine-parseable output with prose on the same stream.

## Agent backend interface

The OCaml-internal signature retained for type-level wiring inside k4k:

```ocaml
module type Agent_backend = sig
  type t
  type config

  val name : string
  val version : t -> string

  val create : config -> t

  val invoke :
    t ->
    purpose:[`Formalization | `Gap_step | `Kb_regen] ->
    prompt:string ->
    budget:int ->
    [ `Ok of response
    | `Budget_exhausted
    | `Tool_error of string ]

  type response = {
    text : string;
    budget_used : int;
    duration_ms : int;
  }
end
```

**The signature is internal scaffolding only.** It has exactly two production-grade implementations: `Backend_external` (the generic adapter that delegates to a configured external executable per `external/backend-protocol.md`) and `Backend_stub` (test harness). Adding new backends does not add new modules — it adds new external executables conforming to the wire protocol.

### Pre-conditions
- `prompt` ≤ backend's effective context window (caller must pre-trim).
- `budget` > 0.

### Post-conditions
- `response.text` is the raw output. Any structure (JSON, diff) is parsed by the caller, not the backend.
- `budget_used` ≤ `budget` for `Ok` responses. `Budget_exhausted` returned with no text otherwise.
- The adapter never raises; all failures are `Tool_error`.

### Determinism contract

The backend itself is **not** required to be deterministic. The harness's determinism is preserved by canonicalizing the response (`algorithms.md#canonicalize`) and by the two-run protocol (`algorithms.md#formalization`).

### Public extension surface

Adding a backend is **not** an OCaml change. It is a new executable conforming to the wire protocol in `external/backend-protocol.md`. The user configures the executable via the interaction file's `k4k.backend.command` frontmatter field. No code in `lib/` is backend-specific.

### Reference backend

`examples/backends/claude-code/` ships a reference implementation suitable for users with `claude` (Claude Code) installed. See `external/backend-protocol.md` and the example's own README.

### Weakness-profile design discipline

`conventions/context-economy.md` constrains every prompt template (`prompts/*.md` in this repo) to fit a 7B-class local model's context window and reasoning depth. After ADR-009 these constraints apply to whatever backend the user plugs in — including users who only ever run against Claude. The discipline keeps the prompts portable.

## Verifier interface

The OCaml-internal signature retained for type-level wiring inside k4k:

```ocaml
module type Verifier = sig
  type t
  type config

  val name : string
  val version : t -> string

  val create : config -> t

  val run :
    t ->
    workdir:string ->
    focus:string list ->
    [ `Ok of result
    | `Tool_error of string ]

  type result = {
    by_property : (string * status) list;
    raw_exit_code : int;
    stdout_path : string;
    stderr_path : string;
    duration_ms : int;
  }
  and status = [ `Established | `Contradicted | `Unknown ]
end
```

**The signature is internal scaffolding only.** It has exactly two production-grade implementations: `Verifier_external` (the generic adapter that delegates to a configured external executable per `external/verifier-protocol.md`) and `Verifier_stub` (test harness). Adding new verifiers does not add new modules — it adds new external executables conforming to the wire protocol.

### Pre-conditions
- `workdir` exists and contains the target program's source tree.
- `focus` may be `[]` ⇒ verify all known properties.

### Post-conditions
- `by_property` is a map; properties not in the verifier's coverage map to `Unknown` (not absent — the harness needs to know it has no signal).
- Logs are persisted to `stdout_path` / `stderr_path`. The verifier must not mutate the user's tracked source tree (build artefacts in standard locations excluded by `.gitignore` are fine).
- The adapter never raises; all failures are `Tool_error`.

### Public extension surface

Adding a verifier is **not** an OCaml change. It is a new executable conforming to the wire protocol in `external/verifier-protocol.md`. The user configures the executable via the interaction file's `k4k.verifier.command` frontmatter field. No code in `lib/` is verifier-specific.

### Test-name convention

Tests / theorems / proof obligations are named `P<id>_<slug>` so the verifier executable can map them to property IDs. The convention is **enforced by the verifier executable**, not by k4k. The k4k-side prompt template `prompts/gap-step.md` instructs the agent to use the convention; conformance is the verifier's job to validate.

### Reference verifier

Per ADR-012, k4k ships **no** reference verifier example: the agent picks the toolchain per project (Rocq + Coq, Frama-C/ACSL, Lean, Verus, F*, dune+alcotest, etc.) and emits the wrapper script as part of its first gap-step. See `external/verifier-protocol.md` for the wire contract any such wrapper must conform to. The pre-v2 `examples/verifiers/dune-ocaml/` was deleted in batch 2's reorientation cleanup; the conformance suite uses `test/conformance/fixtures/synthetic-verifier.sh` as the deterministic stand-in.

## Internal contracts (k4k boundary)

### Reading the interaction file
A pure function `parse : string -> (interaction_file, parse_error) result`. No I/O beyond the read itself; no agent calls. Called twice per run: once for stability, once at the start of each gap-step (re-read).

### Writing the interaction file
A function `append_clarification : interaction_file -> question list -> unit` implemented in `lib/cotype.ml` that goes through cotype: `cotype open` → splice a new `## k4k:clarification:<timestamp>` Markdown section at the end → `cotype save --base-sha <captured> --actor agent:k4k`. Conflict outcomes (user edited a `## k4k:clarification:*` section) surface as `ESTATE_CORRUPT` with the conflict path; k4k itself never calls `flock` (cotype handles its sidecar lock internally).

### Composing prompts
A pure function from `(purpose, D, S, Property?)` to `string`. No randomness. The output is logged verbatim to `agent-runs/<id>/prompt.md` so audits can replay.

## Agent notes

> **Pluggable means pluggable.** The agent and verifier interfaces are signatures, not abstract base classes with default behavior. The harness must work with *any* implementation that satisfies the contract, including a deliberately-degraded one used in tests (`Stub_agent`, `Stub_verifier`).
>
> **Local LLM context budget.** Every prompt template lives in `prompts/` (planned, in source). When you author one, target the smallest context that yields a correct response on the weakest supported backend (Ollama-class). See `conventions/context-economy.md`.

## Related files

- `external/backend-protocol.md` — the wire protocol agent backends must implement
- `external/verifier-protocol.md` — the wire protocol verifiers must implement
- `external/ollama.md` — architectural guidance for prompt-design constraints under the weakness profile
- `architecture/decisions/adr-003-pluggable-backend.md` — pluggable-backend rationale (partially superseded by ADR-009)
- `architecture/decisions/adr-008-verifier-protocol.md` — why the verifier surface is a wire protocol, not an OCaml signature
- `architecture/decisions/adr-009-backend-protocol.md` — symmetric move for backends
- `architecture/overview.md` — module boundaries that realize these contracts
