(** Internal hand-written YAML frontmatter scanner used by [Parser].

    Only the two fields k4k actually consumes ([k4k.version] and [class])
    are extracted; any other YAML constructs are tolerated and ignored.
*)

type fm = { version : int; cls : string; raw : string; after : int }

let raise_format ~line ~col reason =
  raise (Error.K4k_error (Error.E_format { line; col; reason }))

let supported_versions = [ 1 ]

let split_lines s = String.split_on_char '\n' s

let line_starts_with l prefix =
  let lp = String.length prefix in
  String.length l >= lp && String.sub l 0 lp = prefix

let value_after_prefix l prefix =
  let lp = String.length prefix in
  String.trim (String.sub l lp (String.length l - lp))

let find_field body key =
  let prefix = key ^ ":" in
  List.find_map (fun l ->
    let l = String.trim l in
    if line_starts_with l prefix
    then Some (value_after_prefix l prefix)
    else None
  ) (split_lines body)

let int_field body key =
  match find_field body key with
  | None   -> None
  | Some v -> (try Some (int_of_string v) with _ -> None)

let scan_close_marker raw =
  let close = "\n---\n" in
  let n = String.length close in
  let len = String.length raw in
  let rec scan i =
    if i + n > len then -1
    else if String.sub raw i n = close then i
    else scan (i + 1)
  in
  scan 4

let parse raw =
  if not (String.length raw >= 4 && String.sub raw 0 4 = "---\n") then
    raise_format ~line:1 ~col:1 "missing leading '---' frontmatter fence";
  let close_at = scan_close_marker raw in
  if close_at < 0 then
    raise_format ~line:1 ~col:1 "missing closing '---' frontmatter fence";
  let body = String.sub raw 4 (close_at - 4) in
  let version = match int_field body "version" with
    | Some v -> v
    | None -> raise_format ~line:1 ~col:1 "missing 'version' in frontmatter"
  in
  let cls = match find_field body "class" with
    | Some s -> s
    | None -> raise_format ~line:1 ~col:1 "missing 'class' in frontmatter"
  in
  if not (List.mem version supported_versions) then
    raise (Error.K4k_error
      (Error.E_version { found = version; supported = supported_versions }));
  if cls <> "cli" then
    raise (Error.K4k_error (Error.E_class_unsupported cls));
  { version; cls; raw = body; after = close_at + 5 }
