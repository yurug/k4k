(** [Starter_template] — see [.mli]. Pure-string. *)

let frontmatter =
  "---\nk4k:\n  version: 1\n  class: cli\n---\n"

let how_to_use_block =
  "## How to use this file\n\
   This is your interaction file with k4k. Describe in prose what you\n\
   want the program to do; k4k will read your edits, ask clarifying\n\
   questions in-line (as `## k4k:clarification:*` blocks), and once\n\
   the spec stabilizes will develop + verify the program autonomously.\n\
   \n\
   You only edit the user-owned sections below (Goal, Inputs and\n\
   outputs, etc). k4k-managed sections (`## k4k:*`) are written by\n\
   the watcher; do not edit them except where the block says so\n\
   (e.g. `request: rollback` in `## k4k:status`).\n\
   \n\
   Save the file as you would any other; cotype handles concurrency\n\
   between you and k4k.\n\n"

let user_owned_skeleton =
  "## Goal\n\
   (describe what the program should do; one or two paragraphs)\n\n\
   ## Inputs and outputs\n\
   - argv: ...\n\
   - stdin: ...\n\
   - stdout: ...\n\
   - stderr: ...\n\
   - exit codes: ...\n\n\
   ## Error taxonomy\n\
   - ...\n\n\
   ## File-system contract\n\
   N/A\n\n\
   ## Concurrency\n\
   N/A\n\n\
   ## Performance bounds\n\
   N/A\n\n\
   ## Acceptance examples\n\
   1. ...\n\n\
   ## Refusing examples\n\
   1. ...\n\n\
   ## Out of scope\n\
   - ...\n\n"

let welcome_block =
  "## k4k:welcome\n\
   Welcome to k4k. The file you are editing is the entire interface\n\
   between you and the watcher. Write what you want the program to do\n\
   in the user-owned sections above. The first time you save, k4k\n\
   will read your prose and (if it is precise enough) start working;\n\
   otherwise it will append `## k4k:clarification:*` blocks asking\n\
   for what it needs.\n\
   \n\
   This block auto-deletes after the first clarification round\n\
   resolves.\n"

let render ~name =
  let title = "# " ^ name ^ "\n\n" in
  String.concat ""
    [ frontmatter; title; how_to_use_block;
      user_owned_skeleton; welcome_block ]

let has_frontmatter content =
  let prefix = "---\n" in
  String.length content >= 4 && String.sub content 0 4 = prefix

let auto_frontmatter content =
  if has_frontmatter content then content
  else frontmatter ^ content
