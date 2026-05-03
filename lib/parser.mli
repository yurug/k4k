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

(** A parsed ownership-tagged section. [start_offset]/[end_offset] are
    byte offsets into the original file content (exclusive of the
    [<!-- ... -->] delimiters); [content] is the inclusive substring of
    [content[start_offset .. end_offset)]. *)
type section = {
  owner        : [ `User | `K4k ];
  id           : string;
  hash         : string option;       (* set when [owner = `K4k] *)
  content      : string;              (* body bytes, no delimiters *)
  start_offset : int;
  end_offset   : int;
  begin_line   : int;                 (* 1-based line of the begin marker *)
}

(** Parsed frontmatter — fields k4k consumes from the YAML head. *)
type frontmatter = {
  version     : int;
  cls         : string;               (* the [class] value, e.g. "cli" *)
  raw         : string;               (* the bytes between the [---] fences *)
  verifier_command   : string list option;  (* k4k.verifier.command *)
  verifier_timeout_s : int option;          (* k4k.verifier.timeout_s *)
  backend_command    : string list option;  (* k4k.backend.command *)
  backend_timeout_s  : int option;          (* k4k.backend.timeout_s *)
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
