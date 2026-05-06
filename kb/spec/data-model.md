---
id: spec.data-model
type: spec
summary: Schemas for every k4k entity — Property, Characterization, Manifest, AgentRun, VerifierRun — plus the `cli` coverage checklist.
domain: spec
last-updated: 2026-05-02
depends-on: [glossary]
refines: []
related: [spec.algorithms, spec.api-contracts, spec.config-and-formats, properties.functional]
---

# Data Model

## One-liner

Every persistent and in-memory entity k4k manipulates, with field types and invariants. Cited from elsewhere as the single source of truth for type shapes.

## Scope

Schemas only. Procedures that consume/produce these entities live in `algorithms.md`. File formats (the on-disk serialization) live in `config-and-formats.md` — this file describes the *types*, that file describes the *bytes*.

## Property

```
Property = {
  id:             string                               // stable, e.g. "P7"
  statement:      string                               // one-sentence claim
  status:         "required" | "established" | "contradicted" | "unknown"
  evidence:       ArtefactRef[]                        // verifier-runs, agent-runs that bear on this
  risk_score:     float in [0.0, 1.0]                  // computed by `algorithms.md#risk-score`
  failure_count:  int >= 0                             // # consecutive verifier rejections; ≥3 ⇒ "blocked"
  blocked:        bool                                 // mirror of failure_count >= 3
  source:         AspectRef                            // pointer back to the formal-characterization entry that produced this
}
ArtefactRef = { kind: "agent-run" | "verifier-run", id: string }
AspectRef   = { aspect: string, path: string[] }       // e.g. {aspect:"error-taxonomy", path:["EBADARG","when"]}
```

Invariants:
- `id` is unique within the `D` of a given run, stable across runs while the underlying aspect's structural fingerprint is unchanged. See `algorithms.md#property-ids`.
- `failure_count` is incremented on verifier rejection and on agent-budget exhaustion. Reset to 0 only when the user changes `D` such that the property's `source` aspect changes.
- `status = "established"` ⟹ at least one `ArtefactRef` of kind `verifier-run` in `evidence` whose result confirms the property.

## Characterization

The internal AST that represents a desired (`D`) or current (`S`) program characterization. Both share the schema; they differ only in how they are computed.

```
Characterization = {
  class:          "cli"                                // v0: only this
  goal:           string                               // prose, the user's "## Goal"
  inputs_outputs: IOSchema                             // see below
  errors:         ErrorEntry[]                         // see below
  fs_contract:    FSContract                           // see below
  concurrency:    string                               // free-form, may be "N/A"
  perf:           string                               // free-form, may be "N/A"
  examples_accept: AcceptanceExample[]                 // ≥3
  examples_refuse: RefusingExample[]                   // ≥1
  out_of_scope:   string[]
  verifier_pref:  string?                              // optional
  hash:           string                               // SHA-256 of canonicalized form
}
IOSchema = {
  argv:           ArgSpec[]
  stdin:          StreamSpec
  stdout:         StreamSpec
  stderr:         StreamSpec
  exit_codes:     ExitCodeEntry[]
}
ArgSpec        = { name, kind: "flag"|"option"|"positional", type, required: bool, repeats: bool, doc: string }
StreamSpec     = { type: "text"|"binary"|"none", encoding: "utf-8"|null, doc: string }
ExitCodeEntry  = { code: int, condition: string }
ErrorEntry     = { id: string, when: string, message_template: string, exit_code: int }
FSContract     = { reads: PathPattern[], writes: PathPattern[], creates: PathPattern[] }
PathPattern    = { glob: string, mode: "r"|"w"|"rw" }
AcceptanceExample = { name, argv: string[], stdin: string|null, expect: ExampleExpect }
RefusingExample   = { name, argv: string[], stdin: string|null, expect_error: string }   // expect_error matches ErrorEntry.id
ExampleExpect     = { stdout: string, stderr: string, exit_code: int, fs_after: PathSnapshot[]|null }
PathSnapshot      = { path: string, sha256: string }
```

The `hash` is computed *after* canonicalization (see `algorithms.md#canonicalize`). Two characterizations are equivalent iff their hashes match.

## Manifest (`.k4k/manifest.json`)

```
Manifest = {
  k4k_version:        string
  agent_backend:      { name: string, version: string }
  verifier:           { name: string, version: string }
  interaction_file:   { path: string, sha256: string, last_user_section_hashes: { [section_id]: string } }
  desired:            { path: ".k4k/characterization/desired/spec.json", hash: string, last_stable_at: timestamp }
  current:            { path: ".k4k/characterization/current/spec.json", hash: string, last_verified_at: timestamp }
  gap:                { path: ".k4k/gap/properties.json", hash: string, count: int }
  budget:             { soft_per_step: int, hard_per_invocation: int, used: int }
  kb_source_map:      { [kb_file_path]: AspectRef[] }      // keys: paths relative to .k4k/ (e.g. "spec/data-model.md"); used for incremental KB regeneration
  retention:          { agent_runs_keep: int, verifier_runs_keep: int }
}
```

The manifest is regenerated atomically on every state change (write to `manifest.json.tmp`, fsync, rename).

## AgentRun (`.k4k/agent-runs/<id>/`)

```
AgentRun = {
  id:           string                               // <YYYY-MM-DD-HH-MM-SS>-<rand>
  purpose:      "formalization" | "gap-step" | "kb-regen"
  property_id:  string?                              // present when purpose = "gap-step"
  prompt_path:  ".k4k/agent-runs/<id>/prompt.md"
  response_path: ".k4k/agent-runs/<id>/response.md"
  diff_path:    ".k4k/agent-runs/<id>/diff.patch"  // empty for formalization/kb-regen
  verdict_path: ".k4k/agent-runs/<id>/verdict.json"
  budget_used:  int
  duration_ms:  int
  outcome:      "applied" | "rejected" | "budget-exhausted" | "tool-error"
}
```

## VerifierRun (`.k4k/verifier-runs/<id>/`)

```
VerifierRun = {
  id:            string
  trigger:       "initial" | "post-patch" | "explicit-check"
  stdout_path:   ".k4k/verifier-runs/<id>/stdout.log"
  stderr_path:   ".k4k/verifier-runs/<id>/stderr.log"
  result_path:   ".k4k/verifier-runs/<id>/result.json"
  result:        VerifierResult
}
VerifierResult = {
  by_property:   { [property_id]: "established" | "contradicted" | "unknown" }
  raw_exit_code: int
  duration_ms:   int
}
```

## Coverage checklists

Class-keyed lists of *aspects* an interaction file must cover for stability.

```
CoverageChecklist["cli"] = [
  "goal",
  "inputs_outputs.argv",
  "inputs_outputs.stdout",
  "inputs_outputs.stderr",
  "inputs_outputs.exit_codes",
  "errors",                           // ≥1 ErrorEntry; or explicit "no error paths" annotation
  "fs_contract",                      // or "N/A" with rationale
  "concurrency",                      // free-form, "N/A" allowed
  "perf",                             // free-form, "N/A" allowed
  "examples_accept",                  // ≥3
  "examples_refuse",                  // ≥1
  "out_of_scope"
]
```

Coverage of an aspect requires the interaction file to *mention it non-trivially* AND the formalization pass to produce a non-trivial entry for it. `"N/A"` with rationale counts as non-trivial; an empty section does not.

## File ownership marker

The mechanism varies by file:

- **Interaction file** (`<name>.k4k`): post-ADR-010, ownership is *positional* (k4k writes only `## k4k:clarification:*` Markdown sections; everything else is the user's) and **concurrency is delegated to cotype** (`external/cotype.md`). No in-document ownership markers; no `content_hash` attribute. Conflicts surface as cotype `conflict` outcomes, not as hash mismatches.
- **Target-KB files under `.k4k/`**: YAML frontmatter `owner: user | k4k`, `content_hash: <sha256>`. The k4k-owned variant additionally carries a `content_hash` of the body. On read, k4k recomputes the hash; mismatch ⇒ ownership flips to `user` for the run and k4k logs `ownership.flip`. (cotype is intentionally NOT applied to target-KB files in v0; see ADR-006/007.)

## Agent notes

> The boundary between "what" and "how" is rigid. Anything procedural (canonicalization, hashing inputs, ID assignment) belongs in `algorithms.md`. If you find yourself adding "the procedure to ..." here, stop and link.
>
> Field naming is `snake_case` in JSON, mirrored as `snake_case` in OCaml records too — no auto-translation. Justification: keeps the on-disk and in-memory representations diff-able.

## Related files

- `spec.algorithms` — how these entities are produced and consumed
- `spec.config-and-formats` — on-disk byte layout (paths, file formats, frontmatter examples)
- `spec.api-contracts` — interface signatures that take/return these entities
- `properties.functional` — invariants ranging over these schemas
