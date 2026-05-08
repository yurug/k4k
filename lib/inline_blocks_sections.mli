(** [Inline_blocks_sections] — pure section-locator helpers used by
    the file-pruning rules (ADR-011 §7) and by [Tradeoff_flow].

    All functions are byte-pure: no allocation beyond the explicit
    return value, no I/O. *)

(** [find_section raw ~name] — return [Some (start, stop)] for the
    H2 block `## <name>` (start at the '#', stop at the next H2 or
    end-of-string). *)
val find_section : string -> name:string -> (int * int) option

(** [delete_section_named raw ~name] — return [raw] with the H2
    section `## <name>` removed. Idempotent when absent. *)
val delete_section_named : string -> name:string -> string

(** [replace_section_with_breadcrumb raw ~name ~breadcrumb] —
    replace the section `## <name>` with [breadcrumb] (typically an
    HTML-comment line so it renders invisibly). *)
val replace_section_with_breadcrumb :
  string -> name:string -> breadcrumb:string -> string

(** [breadcrumb_for kind ts] = `<!-- k4k:<kind> <ts> — resolved; archived -->`. *)
val breadcrumb_for : string -> string -> string

val find_tradeoff_block :
  string -> (string * string * int * int) option

val find_clarification_block :
  string -> (string * int * int) option

val has_welcome_section : string -> bool

val has_resolved_clarification_breadcrumb : string -> bool
