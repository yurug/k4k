---
vars: [property_id, property_statement, aspect_path, language, verifier_command, current_source_summary]
---

You produce ONE unified-diff patch establishing a single property at
**Tier B — formal model + intensive testing**. The user signed off on
this tier after a Tier-A attempt failed; the proposal is recorded in
the in-flight `## k4k:tradeoff:proposal:*` block.

The patch must:
1. Formalize the property as a model spec (e.g. a relational predicate,
   a state machine, an algebraic property) in `{{language}}`.
2. Hand-write the implementation that the model abstracts.
3. Add property-based tests + a fuzzing entry point that exercise the
   property against the implementation. Tests are named `P<id>_<slug>`
   with `<id>` matching `{{property_id}}` exactly.
4. Update the wrapper script (`{{verifier_command}}`) so it runs the
   test + fuzzing pass and maps results to property statuses per
   `kb/external/verifier-protocol.md`.

## Property to satisfy

- ID: `{{property_id}}`
- Statement: {{property_statement}}
- Aspect path: {{aspect_path}}

## Current source summary

{{current_source_summary}}

## Output format

Output two parts in order, NOTHING else:

1. JSON preface naming touched files:
```json
{"files": ["<path1>", "<path2>"]}
```

2. A unified diff in a fenced code block:
```diff
--- a/<path>
+++ b/<path>
@@ -... +... @@
 ...
```

## Rules

- The model spec is auditable: a reader unfamiliar with the project
  can read the spec and understand what the implementation promises.
- The fuzzing entry point runs in bounded time (~ ≤ 10 s) when invoked
  by the wrapper.
- One diff, one property. No prose between or after the diff.
