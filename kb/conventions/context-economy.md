---
id: conventions.context-economy
type: concept
summary: Prompt design discipline — every agent call must succeed on the weakest supported backend (7B-class local Ollama). Concrete rules, with examples and an enforcement checklist.
domain: conventions
last-updated: 2026-05-02
depends-on: [glossary, external.ollama, architecture.decisions]
refines: []
related: [adr-003, properties.non-functional, external.claude-code]
---

# Context Economy

## Why this convention exists

Round 2 user-added: k4k must work with local Ollama-served models. Those models have smaller context windows, weaker reasoning, brittle JSON output. Designing prompts against Claude and "porting later" never works — the gap between Claude and a 7B model is qualitative, not quantitative. Every prompt is authored against the weak target from day one.

This convention is enforced by `NF8` and exercised by `Backend_stub`'s weakness profile in CI.

## Hard rules

### R1 — Token budgets per call

| Call purpose      | Max input tokens | Max output tokens | Rationale                                |
|-------------------|-------------------|--------------------|------------------------------------------|
| Formalization     | 3 000             | 1 500              | Fits an 8k window with headroom          |
| Gap-step prompt   | 4 000             | 2 000              | Includes scratch context; tighter on Claude is fine |
| KB-regen file     | 1 500             | 1 000              | One file at a time                       |

A prompt that exceeds the input cap is a build failure. Lint check on `prompts/*.md`.

### R2 — Flat output schemas

JSON output schemas in prompts must be flat enough that a 7B model produces them reliably. Concrete:
- ≤ 3 levels of nesting.
- ≤ 12 fields total.
- Field names ≤ 20 chars.
- No optional fields with subtle semantics — make optionality explicit (`null` or absent, never both).

Nested structures are decomposed into multiple calls.

### R3 — One transformation per prompt

A prompt requests one transformation: one input type → one output type. Forbidden:
- "Translate the spec AND check the examples for consistency." (two outputs)
- "Apply the patch AND list the tests you wrote." (two outputs of different shape)

Required: each transformation is its own `invoke` call. If two transformations share inputs, this is fine — pay the input cost twice; do not bundle the outputs.

### R4 — Concrete examples > abstractions

Every prompt template ends with a *one-shot example* (input + expected output) when feasible. Few-shot beats zero-shot at small scale.

### R5 — No CoT beyond 3 steps

Chain-of-thought instructions are limited to 3 explicit reasoning steps. Multi-step reasoning is decomposed into multiple prompts whose outputs become the next prompt's inputs.

### R6 — No reliance on agent judgment for validity

Per `P17`: state transitions never gate on agent self-assessment. The prompt may ask the agent to *propose*, but never to *validate*.

### R7 — Permissive output parsing, strict downstream

The output parser tolerates:
- Markdown code fences around JSON (````json ... ````).
- Trailing prose after the JSON body.
- Trailing commas (light tolerance).

After permissive extraction, the JSON is validated against a strict schema with no extra-field tolerance. Strictness lives downstream.

### R8 — Explicit cap on prompt-internal references

Prompts may not include "as we discussed" or "you previously said" — there is no conversation memory in headless mode. Each call is self-contained. Cross-call state lives in `.k4k/` and is explicitly serialized into the next prompt.

## The "Claude-only smell"

Patterns that work on Claude and fail on Ollama. Each is a smell that triggers a re-write:

- "Think carefully about ..." — small models think carelessly anyway; concretize the question.
- "Consider all possible edge cases ..." — list them yourself in the prompt.
- "Use your judgment to ..." — forbidden by R6; concretize the criterion.
- Multi-paragraph free-form instructions — decompose.
- Schemas with `oneOf` / discriminated unions over many variants — flatten or split into multiple calls.

## Enforcement

### CI checks
1. `prompts/*.md` token count (via `tiktoken` or equivalent) ≤ R1 caps.
2. Each prompt's output schema parsed and structurally compared against R2 limits.
3. `Backend_stub` weakness profile runs the entire test suite. If any test passes only on Claude, the test is wrong (or the prompt is).

### Audit pass
The Phase-5 audit runs every prompt against `Backend_stub`'s weak profile and reports any divergence vs. Claude's output. Divergence > 5% on canonicalized output is a critical finding.

## Worked example: formalization prompt

**Bad** (works on Claude, fails on 7B):
```
Translate the following user spec into a formal characterization. Think carefully
about edge cases and error paths. Output a comprehensive JSON object capturing
every field implied by the user's words.
```

**Good**:
```
Convert the user-owned sections below into the JSON object specified in the
schema at the bottom. Output ONLY the JSON, in a markdown fenced block.

User-owned sections:
{{user_sections}}

Schema (flat; all fields required, "N/A" allowed for free-form fields):
{
  "class":            "cli",
  "goal":             "<= 200 chars",
  "argv":             [{"name":"...", "kind":"flag|option|positional", "type":"string|int|bool", "required":true|false}],
  ...
}

Example input:
{{example_input}}

Example output:
{{example_output}}
```

## Agent notes

> **The cost of being too aggressive on Claude is invisible.** A prompt that uses 6k tokens on Claude works fine until the day someone tries Ollama; then the whole pipeline collapses. The fix is now, not later. Re-read R1 if you find yourself padding context.

## Related files

- `architecture/decisions/adr-003-pluggable-backend.md` — the load-bearing decision
- `external/ollama.md` — the capability profile this convention targets
- `properties/non-functional.md#NF8` — the invariant
- `external/claude-code.md` — the v0 backend (overshoot capacity is fine, just don't use it)
