(** [Parser] — pure parse of an interaction file.

    This module is responsible for translating the on-disk byte string of an
    [.k4k] file into a structured [interaction_file] value. It implements
    P1 (ownership inviolability — by exposing the exact byte ranges of
    user-owned regions for round-trip checking) and the structural half of
    P2.

    Key design decisions: pure (no I/O); rejects non-UTF-8 (T6); does not
    rely on a YAML library — only [k4k.version] (int) and [class] (string)
    are required and are extracted by a tiny hand-written scanner.
*)

(** A parsed Markdown H2 section. Per ADR-010 the section ID is
    derived from the heading text by normalization (lowercase; runs of
    non-alphanumeric → '-'; trailing '-' trimmed). [owner = `K4k]
    iff the section heading matches `## k4k:clarification:*`; all
    other H2 sections are user-owned. The [hash] field is always
    [None] (legacy from ADR-002; retained for API stability). *)
type section = {
  owner        : [ `User | `K4k ];
  id           : string;
  hash         : string option;       (* legacy; always None post-ADR-010 *)
  content      : string;              (* body bytes following the heading *)
  start_offset : int;
  end_offset   : int;
  begin_line   : int;                 (* 1-based line of the heading *)
}

(** Parsed frontmatter — only the two fields v2 honors per ADR-011 /
    [kb/spec/config-and-formats.md]. The verifier command lives on
    [Characterization.verifier_command] (the agent emits it,
    ADR-012); the backend is configured at the operator level via
    [K4K_BACKEND_COMMAND]. *)
type frontmatter = {
  version     : int;
  cls         : string;               (* the [class] value, e.g. "cli" *)
  raw         : string;               (* the bytes between the [---] fences *)
}

(** A parsed interaction file. *)
type interaction_file = {
  raw          : string;
  frontmatter  : frontmatter;
  sections     : section list;        (* in source order *)
}

(** [parse content] parses [content] (the raw bytes of an interaction file).

    @raise Error.K4k_error E_encoding   on invalid UTF-8.
    @raise Error.K4k_error E_format     on unparseable frontmatter,
                                        unmatched/duplicate ids, malformed tags.
    @raise Error.K4k_error E_version    on unknown [k4k.version].
    @raise Error.K4k_error E_class_unsupported on non-CLI [class].
    @invariant P1 — section bytes are returned verbatim. *)
val parse : string -> interaction_file

(** [check_utf8 content] checks that [content] is valid UTF-8.

    @raise Error.K4k_error E_encoding with the byte offset of the first
                                      invalid sequence. *)
val check_utf8 : string -> unit

(** [supported_versions] is the closed list of [k4k.version] values this
    build accepts. *)
val supported_versions : int list

(** [required_user_section_ids] — the canonical list of section ids that
    must be present (per [spec/config-and-formats.md]). *)
val required_user_section_ids : string list
