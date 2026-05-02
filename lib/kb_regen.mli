(** [Kb_regen] — incremental, ownership-aware regeneration of the
    target program's KB inside [.k4k/].

    This module implements [kb/spec/algorithms.md#kb-regen] for v0.
    The [kb_source_map] is a static table mapping each of the 6
    target-KB files to the [Characterization] aspects it depends on:
    {ul
      {- [INDEX.md] — references everything (cheap regen)}
      {- [GLOSSARY.md] — derived from goal + acceptance examples}
      {- [spec/data-model.md] — IO, errors, fs}
      {- [spec/algorithms.md] — accept + refuse examples}
      {- [properties/functional.md] — every aspect that maps to a property}
      {- [properties/edge-cases.md] — refuse examples}
    }

    Ownership detection is hash-based per [kb/properties/edge-cases.md#T18]:
    a file whose recorded [content_hash] no longer matches its body
    bytes is treated as user-owned for this run; k4k never overwrites
    it and never edits its frontmatter (P14, P1).

    @invariant P1 — never writes inside an [owner=user] region.
    @invariant P14 — hash mismatch on a [k4k]-owned file flips ownership
                    for the run and emits an [ownership.flip] event.
    @invariant P16 — only files affected by changed aspects are
                    regenerated.
*)

(** Fixed v0 list of target-KB files (paths relative to the [.k4k/]
    directory). *)
val target_files : string list

(** [aspects_for path] — the static [kb_source_map] entry for [path].
    Returns the list of aspect names (e.g. ["goal"; "examples_accept"])
    this file depends on. Returns [[]] for unknown paths. *)
val aspects_for : string -> string list

(** [diff_aspects ~prev ~current] — aspects that differ between two
    [Characterization.t] values. The strings come from the static
    map's vocabulary. *)
val diff_aspects :
  prev:Characterization.t option ->
  current:Characterization.t ->
  string list

(** [files_affected_by ~changed] — every target file whose static
    aspect list intersects [changed]. *)
val files_affected_by : changed:string list -> string list

(** [is_owned_by_k4k ~k4k_dir ~rel_path] — true iff the file at
    [.k4k/<rel_path>] either does not exist yet OR its recorded
    [content_hash] frontmatter matches the body bytes verbatim.
    Returns [true] for missing files (k4k may create them).

    @invariant P14. *)
val is_owned_by_k4k : k4k_dir:string -> rel_path:string -> bool

(** [render_file ~rel_path ~d] — produce the body (frontmatter + content)
    for [rel_path] from the canonicalized [Characterization.t] [d].
    The frontmatter contains [id], [type], [summary], [domain],
    [last-updated], [owner: k4k], [content_hash]. The body is
    deterministic given [d]. *)
val render_file : rel_path:string -> d:Characterization.t -> string

(** [regen ~k4k_dir ~prev_d ~current_d ~logger] — regenerate every
    target file affected by aspect changes between [prev_d] and
    [current_d], skipping any file whose ownership has flipped to
    user. Emits one [ownership.flip] log event per skipped file.

    @invariant P14, P16. *)
val regen :
  k4k_dir:string ->
  prev_d:Characterization.t option ->
  current_d:Characterization.t ->
  logger:Logger.t ->
  unit

(** [regen_full ~k4k_dir ~current_d ~logger] — regenerate every
    target file (initial run). Equivalent to [regen] with
    [prev_d = None]. Honors ownership flips. *)
val regen_full :
  k4k_dir:string ->
  current_d:Characterization.t ->
  logger:Logger.t ->
  unit
