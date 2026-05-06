(** Parse Markdown body into H2 sections. Pure, no I/O.

    Per ADR-010, sections are delimited by `## ` headings; the section
    ID is derived from the heading text by [normalize_id] (lowercase;
    runs of non-alphanumeric chars → '-'; trim trailing '-').

    A section heading matching `## k4k:clarification:<rest>` is
    k4k-managed; all other sections are user-owned. *)

type owner = [ `User | `K4k ]

type section = {
  owner        : owner;
  id           : string;
  hash         : string option;        (* always None post-ADR-010 *)
  content      : string;
  start_offset : int;
  end_offset   : int;
  begin_line   : int;
}

let raise_format ~line ~col reason =
  raise (Error.K4k_error (Error.E_format { line; col; reason }))

let line_of_offset s off =
  let n = ref 1 in
  for i = 0 to min (off - 1) (String.length s - 1) do
    if s.[i] = '\n' then incr n
  done;
  !n

(* lowercase + replace runs of non-[a-z0-9] with single '-'; trim
   trailing '-'. Matches kb/spec/config-and-formats.md#section-identification. *)
let normalize_id heading =
  let buf = Buffer.create (String.length heading) in
  let last_dash = ref true in
  String.iter (fun c ->
    let lc = Char.lowercase_ascii c in
    let is_alnum = (lc >= 'a' && lc <= 'z') || (lc >= '0' && lc <= '9') in
    if is_alnum then begin Buffer.add_char buf lc; last_dash := false end
    else if not !last_dash then
      begin Buffer.add_char buf '-'; last_dash := true end
  ) heading;
  let s = Buffer.contents buf in
  let n = String.length s in
  if n > 0 && s.[n - 1] = '-' then String.sub s 0 (n - 1) else s

let is_clarification_id id =
  let prefix = "k4k-clarification" in
  let lp = String.length prefix in
  String.length id >= lp && String.sub id 0 lp = prefix

(* Find the start-of-line index for byte offset [off]. *)
let line_start s off =
  let rec back i =
    if i <= 0 then 0
    else if s.[i - 1] = '\n' then i
    else back (i - 1)
  in back off

(* Iterate H2 lines (lines starting with "## "). Return a list of
   (heading_text_offset, heading_text, line_start, next_line_start). *)
let h2_lines s start =
  let n = String.length s in
  let acc = ref [] in
  let i = ref start in
  let line_no_start = ref (line_start s start) in
  while !i < n do
    let lstart = !line_no_start in
    (* find end of line *)
    let j = ref !i in
    while !j < n && s.[!j] <> '\n' do incr j done;
    let next = if !j < n then !j + 1 else !j in
    if !j - lstart >= 3
       && s.[lstart] = '#' && s.[lstart + 1] = '#' && s.[lstart + 2] = ' '
    then begin
      let txt = String.sub s (lstart + 3) (!j - (lstart + 3)) in
      acc := (lstart, String.trim txt, lstart, next) :: !acc
    end;
    i := next;
    line_no_start := next
  done;
  List.rev !acc

let build_sections raw start =
  let headings = h2_lines raw start in
  let n = String.length raw in
  let rec loop seen acc = function
    | [] -> List.rev acc
    | (heading_start, txt, _, after_heading) :: rest ->
        let id = normalize_id txt in
        if id = "" then
          raise_format ~line:(line_of_offset raw heading_start) ~col:1
            (Printf.sprintf "empty section id from heading: %S" txt);
        if List.mem id seen then
          raise_format ~line:(line_of_offset raw heading_start) ~col:1
            (Printf.sprintf "duplicate section id: %s" id);
        let body_end = match rest with
          | (next_start, _, _, _) :: _ -> next_start
          | [] -> n
        in
        let owner = if is_clarification_id id then `K4k else `User in
        let content = String.sub raw after_heading (body_end - after_heading) in
        let sec = {
          owner; id; hash = None; content;
          start_offset = after_heading;
          end_offset   = body_end;
          begin_line   = line_of_offset raw heading_start;
        } in
        loop (id :: seen) (sec :: acc) rest
  in
  loop [] [] headings

let scan raw start = build_sections raw start
