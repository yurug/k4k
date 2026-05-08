---
vars: [property_id, property_statement, aspect_path, language, verifier_command, current_source_summary]
---

You produce ONE unified-diff patch establishing a single property at
**Tier A — full formal verification** in this project's chosen
language: `{{language}}`.

The patch must:
1. Add or modify code (proof artefacts + extracted/contracted
   implementation) so the property is machine-checked.
2. Add or modify the project's wrapper script (referenced as
   `{{verifier_command}}`) so it conforms to
   `kb/external/verifier-protocol.md` for property `{{property_id}}`.
3. Use idiomatic tactics / annotations for `{{language}}` (e.g.
   SSReflect for Rocq, ACSL for Frama-C/WP, Verus for Rust). Pick what
   you would actually use; we trust your world-knowledge of the tool.

## Property to satisfy

- ID: `{{property_id}}`
- Statement: {{property_statement}}
- Aspect path: {{aspect_path}}

## Current source summary

{{current_source_summary}}

## Output format

Output two parts in order, NOTHING else:

1. JSON preface naming the touched files:
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

- The wrapper script (path = `{{verifier_command}}`) is part of the
  project source. Your patch may extend it to recognize the new
  property id.
- Theorems / proof obligations are named `P<id>_<slug>` where `<id>`
  matches `{{property_id}}` exactly; non-conforming names are reported
  as `unknown` by the verifier.
- One diff, one property. No prose between or after the diff.
