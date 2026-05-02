(** [Prompts] — minimal [{{var}}] substitution + prompt loading per Q3.1.

    Templates are plain Markdown with a YAML frontmatter declaring
    allowed [vars]. Substitution is pure string replacement of [{{name}}]
    tokens; no Mustache logic, no conditionals. *)

(** [substitute template vars] — replaces every occurrence of
    [{{name}}] with its corresponding value. Pure. *)
val substitute : string -> (string * string) list -> string

(** [load name] — reads the prompt template named [name] from
    [prompts/<name>] at the repository root.

    @raise Error.K4k_error E_state_corrupt if the template is missing. *)
val load : string -> string

(** [strip_frontmatter s] — drops the leading [---\n...\n---] block
    if present; otherwise returns [s] unchanged. *)
val strip_frontmatter : string -> string

(** [render name vars] = [substitute (strip_frontmatter (load name)) vars]. *)
val render : string -> (string * string) list -> string
