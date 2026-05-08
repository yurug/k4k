type section = Parser_sections.section = {
  owner        : [ `User | `K4k ];
  id           : string;
  hash         : string option;
  content      : string;
  start_offset : int;
  end_offset   : int;
  begin_line   : int;
}

type frontmatter = {
  version : int;
  cls     : string;
  raw     : string;
}

type interaction_file = {
  raw         : string;
  frontmatter : frontmatter;
  sections    : section list;
}

let supported_versions = Parser_frontmatter.supported_versions

(* Per kb/spec/config-and-formats.md (post-ADR-010): section IDs are
   derived from H2 heading text by normalization (lowercase; runs of
   non-alphanumeric → '-'; trim trailing '-'). The required set
   below is the result of that normalization for the canonical
   heading set documented in spec/config-and-formats.md. *)
let required_user_section_ids = [
  "goal"; "inputs-and-outputs"; "error-taxonomy";
  "file-system-contract"; "concurrency"; "performance-bounds";
  "acceptance-examples"; "refusing-examples"; "out-of-scope";
]

let check_utf8 = Parser_utf8.check

(* T1 — empty file is parsed permissively so [Stability] reports it as
   [Unstable] (not [E_format]). *)
let empty_interaction_file =
  { raw         = "";
    frontmatter = { version = 1; cls = "cli"; raw = "" };
    sections    = [] }

let to_frontmatter (fm : Parser_frontmatter.fm) =
  { version = fm.version; cls = fm.cls; raw = fm.raw }

let parse content =
  let content = Parser_utf8.strip_bom content in
  if content = "" then empty_interaction_file
  else begin
    Parser_utf8.check content;
    let fm = Parser_frontmatter.parse content in
    let sections = Parser_sections.scan content fm.after in
    { raw = content; frontmatter = to_frontmatter fm; sections }
  end
