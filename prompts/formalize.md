---
vars: [user_sections]
---

You convert a user's CLI program specification into a STRICT JSON
object that follows the schema below. Output ONLY the JSON, in a
single fenced code block. No prose before or after. Do not invent
fields. Use "N/A" for free-form fields the user did not provide.

User-owned sections (verbatim, between markers):

{{user_sections}}

Schema (every field is REQUIRED; "fs_after" may be null; "stdin"
may be null):

```
{
  "class": "cli",
  "goal": "<= 200 chars summarizing what the program does",
  "language": "ocaml|rust|c|python|...",
  "verifier_command": ["./_verifier.sh"],
  "inputs_outputs": {
    "argv": [
      {"name": "<flag-or-positional>", "kind": "flag|option|positional",
       "type": "string|int|bool", "required": true|false,
       "repeats": true|false, "doc": "<one line>"}
    ],
    "stdin":  {"type": "text|binary|none", "encoding": "utf-8"|null, "doc": ""},
    "stdout": {"type": "text|binary|none", "encoding": "utf-8"|null, "doc": ""},
    "stderr": {"type": "text|binary|none", "encoding": "utf-8"|null, "doc": ""},
    "exit_codes": [{"code": 0, "condition": "..."}]
  },
  "errors": [
    {"id": "EBADARG", "when": "...",
     "message_template": "...", "exit_code": 1}
  ],
  "fs_contract": {
    "reads":   [{"glob": "...", "mode": "r"}],
    "writes":  [{"glob": "...", "mode": "w"}],
    "creates": [{"glob": "...", "mode": "w"}]
  },
  "concurrency": "N/A",
  "perf": "N/A",
  "examples_accept": [
    {"name": "ex1", "argv": ["..."], "stdin": null,
     "expect": {"stdout": "...", "stderr": "", "exit_code": 0,
                "fs_after": null}}
  ],
  "examples_refuse": [
    {"name": "ref1", "argv": ["..."], "stdin": null,
     "expect_error": "EBADARG"}
  ],
  "out_of_scope": ["..."],
  "verifier_pref": null,
  "hash": ""
}
```

Rules:
- Every example listed in user examples-accept becomes one entry; do not
  invent extra examples.
- Every error tag in user errors becomes one errors[] entry; the "when"
  field comes from the user's prose verbatim.
- Use the user's identifiers verbatim (do not paraphrase flag names or
  error ids).
- "language": choose from the user's prose, or default to a sensible
  match for the verification tier they need (OCaml + Rocq for Tier-A
  formal verification; Rust + Verus; C + Frama-C; etc.). The choice
  participates in the canonical hash — make it deterministic given
  the user's content.
- "verifier_command": the argv (executable + leading args) of the
  wrapper script you (the agent) will write, conforming to
  kb/external/verifier-protocol.md. Typical: ["./_verifier.sh"].
  This is what k4k will invoke for every gap-step verification.
  k4k carries no toolchain knowledge — you pick the verifier per
  project and emit the wrapper.

Worked example
==============

Given these user-owned sections:

```
## Goal
A program named `lower` that takes one positional argument and prints
it in lowercase to stdout, followed by a trailing newline.

## Inputs and outputs
- argv: one positional STRING (required).
- stdin: not read.
- stdout: argv[1] with ASCII letters lowercased; trailing LF.
- stderr: empty on success; one-line message on error.
- exit codes: 0 success, 1 EBADARG.

## Error taxonomy
- EBADARG: when argv count is not exactly 1.

## File-system contract
N/A

## Concurrency
N/A

## Performance bounds
N/A

## Acceptance examples
1. lower HELLO  → stdout "hello\n", exit 0
2. lower x      → stdout "x\n", exit 0
3. lower ""     → stdout "\n", exit 0

## Refusing examples
1. lower        → EBADARG, exit 1

## Out of scope
- Reading from stdin or files.
```

The expected output is exactly:

```json
{
  "class": "cli",
  "goal": "Lowercase the single argv argument and write it to stdout with a trailing LF.",
  "language": "ocaml",
  "verifier_command": ["./_verifier.sh"],
  "inputs_outputs": {
    "argv": [
      {"name": "input", "kind": "positional", "type": "string",
       "required": true, "repeats": false, "doc": "string to lowercase"}
    ],
    "stdin":  {"type": "none", "encoding": null,   "doc": ""},
    "stdout": {"type": "text", "encoding": "utf-8", "doc": "lowercased argument + LF"},
    "stderr": {"type": "text", "encoding": "utf-8", "doc": "error message on failure"},
    "exit_codes": [
      {"code": 0, "condition": "ok"},
      {"code": 1, "condition": "EBADARG"}
    ]
  },
  "errors": [
    {"id": "EBADARG", "when": "argv count is not exactly 1",
     "message_template": "EBADARG: expected 1 arg", "exit_code": 1}
  ],
  "fs_contract": {"reads": [], "writes": [], "creates": []},
  "concurrency": "N/A",
  "perf": "N/A",
  "examples_accept": [
    {"name": "uppercase", "argv": ["HELLO"], "stdin": null,
     "expect": {"stdout": "hello\n", "stderr": "", "exit_code": 0, "fs_after": null}},
    {"name": "single_char", "argv": ["x"], "stdin": null,
     "expect": {"stdout": "x\n", "stderr": "", "exit_code": 0, "fs_after": null}},
    {"name": "empty_string", "argv": [""], "stdin": null,
     "expect": {"stdout": "\n", "stderr": "", "exit_code": 0, "fs_after": null}}
  ],
  "examples_refuse": [
    {"name": "no_args", "argv": [], "stdin": null, "expect_error": "EBADARG"}
  ],
  "out_of_scope": ["Reading from stdin or files."],
  "verifier_pref": null,
  "hash": ""
}
```

If the user's spec is missing fields (e.g., fewer than three acceptance
examples, no refusing examples, ambiguous I/O contract), STILL emit
the JSON with your best inference — use "N/A" for unknown free-form
strings and `[]` for unknown lists. Do NOT respond in prose asking
for clarification: k4k has a separate coverage-check phase that
reports gaps to the user via clarification blocks. Your job is to
emit a typed characterization, even an under-specified one.
