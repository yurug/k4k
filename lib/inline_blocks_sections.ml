(** [Inline_blocks_sections] — pure section-locator helpers extracted
    from [Inline_blocks] (200-line cap). Used by the file-pruning rules
    in ADR-011 §7 and by [Tradeoff_flow]. *)

(* Find the byte range covering the H2 block whose heading exactly
   matches `## <name>` (heading line + body up to the next H2 or EOF).
   Returns [Some (start, stop)] where [start] is the '#' and [stop] is
   the start of the next block (or [String.length raw]). *)
let find_section raw ~name =
  let n = String.length raw in
  let header = "## " ^ name in
  let lh = String.length header in
  let rec scan i =
    if i + lh > n then None
    else if (i = 0 || raw.[i - 1] = '\n')
            && String.sub raw i lh = header
            && (i + lh = n || raw.[i + lh] = '\n')
    then
      let rec scan_end j =
        if j + 3 > n then n
        else if j > i && raw.[j - 1] = '\n'
                && raw.[j] = '#' && raw.[j + 1] = '#'
                && raw.[j + 2] = ' '
        then j
        else scan_end (j + 1)
      in
      Some (i, scan_end (i + lh))
    else scan (i + 1)
  in
  scan 0

let delete_section_named raw ~name =
  match find_section raw ~name with
  | None -> raw
  | Some (start, stop) ->
      String.sub raw 0 start
      ^ String.sub raw stop (String.length raw - stop)

let replace_section_with_breadcrumb raw ~name ~breadcrumb =
  let bc =
    let n = String.length breadcrumb in
    if n > 0 && breadcrumb.[n - 1] = '\n' then breadcrumb
    else breadcrumb ^ "\n"
  in
  match find_section raw ~name with
  | None -> raw
  | Some (start, stop) ->
      String.sub raw 0 start ^ bc
      ^ String.sub raw stop (String.length raw - stop)

let breadcrumb_for kind ts =
  Printf.sprintf "<!-- k4k:%s %s — resolved; archived -->" kind ts

(* Locate the first `## <prefix><ts>` H2 block. Internal helper
   that powers both [find_tradeoff_block] and
   [find_clarification_block] — they used to be 30+ line near-
   duplicates that only differed in the prefix string and the
   return-shape (axis 6 M-2). *)
let find_h2_with_prefix raw ~prefix =
  let n = String.length raw in
  let lp = String.length prefix in
  let line_end_of i =
    let rec go j =
      if j >= n then j
      else if raw.[j] = '\n' then j
      else go (j + 1)
    in go i
  in
  let scan_end_after body_start =
    let rec go j =
      if j + 3 > n then n
      else if j > body_start && raw.[j - 1] = '\n'
              && raw.[j] = '#' && raw.[j + 1] = '#'
              && raw.[j + 2] = ' '
      then j
      else go (j + 1)
    in
    go body_start
  in
  let rec scan i =
    if i + lp > n then None
    else if (i = 0 || raw.[i - 1] = '\n')
            && String.sub raw i lp = prefix
    then
      let line_end = line_end_of (i + lp) in
      let ts = String.trim (String.sub raw (i + lp) (line_end - (i + lp))) in
      let body_start = if line_end < n then line_end + 1 else line_end in
      let stop = scan_end_after body_start in
      Some (ts, body_start, stop, i)
    else scan (i + 1)
  in
  scan 0

(* Find the first `## k4k:tradeoff:proposal:<ts>` block. Returns
   [Some (ts, body, start, stop)] or [None]. *)
let find_tradeoff_block raw =
  match find_h2_with_prefix raw ~prefix:"## k4k:tradeoff:proposal:" with
  | None -> None
  | Some (ts, body_start, stop, start) ->
      let body = String.sub raw body_start (stop - body_start) in
      Some (ts, body, start, stop)

(* Find the first `## k4k:clarification:<ts>` section. Returns
   [Some (ts, start, stop)] or [None]. *)
let find_clarification_block raw =
  match find_h2_with_prefix raw ~prefix:"## k4k:clarification:" with
  | None -> None
  | Some (ts, _body_start, stop, start) -> Some (ts, start, stop)

let has_welcome_section raw = find_section raw ~name:"k4k:welcome" <> None

let has_resolved_clarification_breadcrumb raw =
  let needle = "<!-- k4k:clarification " in
  let n = String.length raw and ln = String.length needle in
  let rec scan i =
    if i + ln > n then false
    else if String.sub raw i ln = needle then true
    else scan (i + 1)
  in
  scan 0
