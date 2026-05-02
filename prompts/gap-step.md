---
vars: [property_id, property_statement, aspect_path, current_source_summary, acceptance_examples, refusing_examples, test_name_convention]
---

You produce ONE unified-diff patch that satisfies a single property in
a target program. The patch must:
1. Add or modify code so the property holds.
2. Add or modify exactly ONE alcotest test named `{{property_id}}_<slug>`
   under the project's `test/` directory; the test must FAIL before
   your patch and PASS after it.

Do NOT touch unrelated tests. Do NOT modify files outside the project.

## Property to satisfy

- ID: `{{property_id}}`
- Statement: {{property_statement}}
- Aspect path: {{aspect_path}}

## Acceptance examples (must continue to pass)

{{acceptance_examples}}

## Refusing examples (must continue to be rejected)

{{refusing_examples}}

## Current source summary

{{current_source_summary}}

## Test naming convention

{{test_name_convention}}

## Output format

Output two parts in order, NOTHING else:

1. A JSON preface naming the files your diff touches:
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
  exactly. A non-conforming name is treated as `Unknown` by the verifier.
- Every property is satisfied by ONE diff and ONE new test.
- No prose between or after the diff. The diff is the last thing.

## Worked example

For a property `P1234567` "satisfy stdout-mirror-argv":

```json
{"files": ["bin/echo.ml", "test/test_echo.ml"]}
```

```diff
--- a/bin/echo.ml
+++ b/bin/echo.ml
@@ -1 +1,2 @@
-let () = ()
+let () = print_endline (String.concat " " (List.tl (Array.to_list Sys.argv)))
--- a/test/test_echo.ml
+++ b/test/test_echo.ml
@@ -1 +1,5 @@
-let () = ()
+let () =
+  Alcotest.run "echo"
+    [ "S", [ Alcotest.test_case "P1234567_stdout_mirror_argv"
+              `Quick (fun () -> ()) ] ]
```
