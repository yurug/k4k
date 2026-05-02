---
id: spec.api-contracts
type: spec
summary: Interfaces k4k depends on — agent backend (pluggable, v0 ships claude-code), verifier (pluggable, v0 ships dune-ocaml) — plus the public CLI contract.
domain: spec
last-updated: 2026-05-02
depends-on: [glossary, spec.data-model, spec.algorithms]
refines: []
related: [external.claude-code, external.dune, external.ollama, architecture.overview]
---

# API Contracts

## One-liner

The interfaces between k4k and the outside world: the public CLI it exposes, the agent-backend interface it consumes, the verifier interface it consumes.

## Scope

Signatures, pre/post-conditions, error contracts. Implementations live in code; runtime behavior of specific backends and verifiers lives in `external/`.

## Public CLI contract

`k4k <subcommand>? <file.k4k> <flags>...`

| Form                                | Pre-conditions                                       | Post-conditions                                                                  | Exit codes                                  |
|-------------------------------------|------------------------------------------------------|----------------------------------------------------------------------------------|---------------------------------------------|
| `k4k <file.k4k>`                    | File exists, ≤ 10 MB, UTF-8, parseable               | If stable & gap empty: `done` on stdout + exit 0. On any failure: exit code per `error-taxonomy.md`, stderr line `k4k: <message>`, no partial mutation of `.k4k/`. | 0, 1, 2, 3, 4, 5                            |
| `k4k --check <file.k4k>`            | Same as above                                        | Prints `stable` or unstable diagnostic; never invokes a gap-step.                | 0 (stable), 1 (unstable)                    |
| `k4k --status <file.k4k>`           | `.k4k/` exists                                       | Prints current gap properties (id, status, risk_score) one per line. No writes.  | 0 always (or 5 if `.k4k/` missing)          |
| `k4k --reset <file.k4k> --yes`      | `--yes` provided                                     | `.k4k/` removed; manifest reinitialized empty.                                   | 0                                           |

Flags: `-v` / `-vv` (verbosity), `--no-color`, `--max-steps N`, `--budget M`. See `error-taxonomy.md` for all exit codes.

### Stdout/stderr discipline (`P.stdout-discipline`)

- **stdout**: only the one-line in-place TTY status, OR (when `!isatty(stdout)`) one structured log line per state transition. Final `done` or error summary on success/failure.
- **stderr**: free-form diagnostics at `-v`/`-vv`; nothing at default verbosity.
- Never mix machine-parseable output with prose on the same stream.

## Agent backend interface

```ocaml
module type Agent_backend = sig
  type t
  type config

  val name : string                          (* "claude-code", "ollama-codellama-7b", ... *)
  val version : t -> string

  val create : config -> t

  val invoke :
    t ->
    purpose:[`Formalization | `Gap_step | `Kb_regen] ->
    prompt:string ->
    budget:int ->                            (* budget units this call may consume *)
    [ `Ok of response
    | `Budget_exhausted
    | `Tool_error of string ]

  type response = {
    text : string;                           (* raw model output *)
    budget_used : int;                       (* tokens-equivalent *)
    duration_ms : int;
  }
end
```

### Pre-conditions
- `prompt` ≤ backend's effective context window (caller must pre-trim).
- `budget` > 0.

### Post-conditions
- `response.text` is the raw output. Any structure (JSON, diff) is parsed by the caller, not the backend.
- `budget_used` ≤ `budget` for `Ok` responses. `Budget_exhausted` returned with no text otherwise.
- The backend never raises; all failures are `Tool_error`.

### Determinism contract

The backend itself is **not** required to be deterministic. The harness's determinism is preserved by canonicalizing the response (`algorithms.md#canonicalize`) and by the two-run protocol (`algorithms.md#formalization`).

### Concrete v0 backend
`claude-code` — see `external/claude-code.md` for invocation surface, runtime behavior, request budget model.

### Architected v1+ backend
`ollama-*` — see `external/ollama.md` and ADR-003. Prompts must be designed against this backend's smaller context window and weaker reasoning, *not* against Claude's.

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

`examples/verifiers/dune-ocaml/` ships a reference implementation for OCaml + dune projects. See `external/verifier-protocol.md` and the example's own README.

## Internal contracts (k4k boundary)

### Reading the interaction file
A pure function `parse : string -> (interaction_file, parse_error) result`. No I/O beyond the read itself; no agent calls. Called twice per run: once for stability, once at the start of each gap-step (re-read).

### Writing the interaction file
A function `append_clarification : interaction_file -> question list -> unit` that adds an `<!-- k4k:owner=k4k begin id=clarification-<ts> hash=... -->` block at the end. Holds `flock` for the duration; never modifies any existing block.

### Composing prompts
A pure function from `(purpose, D, S, Property?)` to `string`. No randomness. The output is logged verbatim to `agent-runs/<id>/prompt.md` so audits can replay.

## Agent notes

> **Pluggable means pluggable.** The agent and verifier interfaces are signatures, not abstract base classes with default behavior. The harness must work with *any* implementation that satisfies the contract, including a deliberately-degraded one used in tests (`Stub_agent`, `Stub_verifier`).
>
> **Local LLM context budget.** Every prompt template lives in `prompts/` (planned, in source). When you author one, target the smallest context that yields a correct response on the weakest supported backend (Ollama-class). See `conventions/context-economy.md`.

## Related files

- `external/claude-code.md` — runtime behavior of the v0 agent backend
- `external/verifier-protocol.md` — the wire protocol verifiers must implement
- `external/ollama.md` — v1+ target, but prompts must already accommodate
- `architecture/decisions/adr-003-pluggable-backend.md` — why these signatures, why now
- `architecture/decisions/adr-008-verifier-protocol.md` — why the verifier surface is a wire protocol, not an OCaml signature
- `architecture/overview.md` — module boundaries that realize these contracts
