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

let required_user_section_ids = [
  "goal"; "inputs-outputs"; "errors"; "fs"; "concurrency";
  "perf"; "examples-accept"; "examples-refuse"; "out-of-scope";
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
