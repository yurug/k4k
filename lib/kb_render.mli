(** [Kb_render] — pure deterministic rendering of target-KB files.

    Split out of [Kb_regen] to keep both files under 200 lines.
    No I/O. *)

(** [render_file ~rel_path ~d] — produce the body (frontmatter + content)
    for [rel_path] from [d]. *)
val render_file : rel_path:string -> d:Characterization.t -> string
