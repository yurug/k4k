(** [Starter_template] — pure: render the starter [.k4k] file used on
    first run when the file does not exist (ADR-011 §3, PRD S1).

    Contains:
    - frontmatter with [k4k.version: 1] and [class: cli]
    - a free-form [# Project] heading
    - a [## How to use this file] explanatory block
    - the required user-owned section headings (per
      [kb/spec/config-and-formats.md] - cli class)
    - a placeholder [## k4k:welcome] block (auto-deletes after the
      first clarification round). *)

(** [render ~name] returns the bytes for a fresh starter file. [name]
    is used in the leading [# <name>] heading; it should be the
    file's stem (no extension). *)
val render : name:string -> string

(** [auto_frontmatter content] — returns [content] with a minimal
    [k4k.version: 1; class: cli] frontmatter prefixed if no [---]
    fence is present. Idempotent on already-frontmattered input. *)
val auto_frontmatter : string -> string
