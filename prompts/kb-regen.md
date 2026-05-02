---
vars: [kb_file_path, aspects_in_scope, current_d_excerpt, current_s_excerpt]
---

You generate ONE knowledge-base markdown file for a target program.

The file lives at `{{kb_file_path}}` inside the `.k4k/` tree of the
target program. It documents the target program's behavior, NOT the
behavior of the k4k harness itself.

## Aspects in scope for this file

{{aspects_in_scope}}

## Current desired-characterization excerpt

{{current_d_excerpt}}

## Current source-characterization excerpt

{{current_s_excerpt}}

## Output format

Output ONLY the file body. The body MUST start with YAML frontmatter
of exactly this shape (replace bracketed values):

```
---
id: <stable-id>
type: <index|spec|concept|procedure>
summary: <one-line summary; <= 200 chars>
domain: <target>
last-updated: 2026-05-02
owner: k4k
content_hash: <left empty; harness fills it>
---
```

After the closing `---`, write the file's content as plain markdown.
Cite only KB-content the formalized characterization actually
established. Do NOT invent invariants or examples not present above.

## Rules

- Single transformation: one input → one output file body.
- No prose before the first `---` and no prose after the last line of
  the body.
- The frontmatter `id` must match a stable identifier derived from the
  file path.
- The body must NOT include the `content_hash` value — leave it empty
  and the harness will compute and persist it deterministically.
- Aspect entries must reflect only what's in [aspects_in_scope]; if an
  aspect is empty, write a single line `- (none specified)`.

## Worked example

For `kb_file_path = "GLOSSARY.md"`, `aspects_in_scope = ["goal",
"examples_accept"]`, the output begins:

```
---
id: GLOSSARY
type: concept
summary: Target program glossary derived from goal + examples
domain: target
last-updated: 2026-05-02
owner: k4k
content_hash: 
---

# Glossary

- **goal**: <verbatim from current_d_excerpt.goal>
- **acceptance examples**: <names from current_d_excerpt.examples_accept>
```
