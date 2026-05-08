(** [Status_splice] — see [.mli]. Line-oriented; no parser dependency
    so it can run before/without [Parser.parse]. *)

let header = "## k4k:status"

(* Find the byte offsets of the `## k4k:status` block. Returns
   [Some (start, end_)] where [start] is the index of the '#' and
   [end_] is the index of the next H2 (or end-of-string). *)
let find_status_block raw =
  let n = String.length raw in
  let h = header in
  let lh = String.length h in
  let rec scan i =
    if i + lh > n then None
    else if String.sub raw i lh = h && (i + lh = n || raw.[i + lh] = '\n')
            && (i = 0 || raw.[i - 1] = '\n')
    then
      (* Find the end: next "## " starting a line, or eof. *)
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

let ensure_trailing_nl s =
  let n = String.length s in
  if n = 0 || s.[n - 1] = '\n' then s
  else s ^ "\n"

let replace_or_append raw block =
  let block = ensure_trailing_nl block in
  match find_status_block raw with
  | Some (start, stop) ->
      String.sub raw 0 start ^ block ^ String.sub raw stop (String.length raw - stop)
  | None ->
      let raw = ensure_trailing_nl raw in
      raw ^ "\n" ^ block
