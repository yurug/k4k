---
vars: [property_id, property_statement, aspect_path, language, verifier_command, prior_failure, current_source_summary]
---

You produce ONE unified-diff patch establishing a single property at
**Tier C — testing-only**. The user signed off on this tier after
acknowledging that the formal-correctness goal is forfeited for this
property (recorded in the in-flight `## k4k:tradeoff:proposal:*` block).

The patch must:
1. Add or modify code in `{{language}}` so the property can be
   exercised by tests.
2. Add or modify exactly ONE test named `P<id>_<slug>` (with `<id>`
   matching `{{property_id}}` exactly) under the project's test
   directory; the test must FAIL before this patch and PASS after it.
3. Add a property-based test for the same property when the property
   is universally quantified (rather than over fixed examples).
4. Update the wrapper script (`{{verifier_command}}`) to run the new
   test and map its outcome per `kb/external/verifier-protocol.md`.

## Property to satisfy

- ID: `{{property_id}}`
- Statement: {{property_statement}}
- Aspect path: {{aspect_path}}

## Previous attempt

{{prior_failure}}

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

- Tests are named `P<id>_<slug>`. The id must equal `{{property_id}}`
  exactly; non-conforming names report as `unknown`.
- Do NOT touch unrelated tests.
- One diff, one property. No prose between or after the diff.
