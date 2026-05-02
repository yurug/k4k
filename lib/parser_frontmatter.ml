(** Internal hand-written YAML frontmatter scanner used by [Parser].

    Extracts the fields k4k actually consumes:
    - [k4k.version], [class] — required
    - [k4k.verifier.command] — list of strings, required for run flow
    - [k4k.verifier.timeout_s] — positive int, optional
    Other YAML constructs are tolerated and ignored.
*)

type fm = {
  version : int;
  cls : string;
  raw : string;
  after : int;
  verifier_command   : string list option;
  verifier_timeout_s : int option;
}

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

(* Trim quotes (single or double) and surrounding whitespace. *)
let unquote s =
  let s = String.trim s in
  let n = String.length s in
  if n >= 2 && (s.[0] = '"' || s.[0] = '\'')
            && s.[n-1] = s.[0]
  then String.sub s 1 (n - 2)
  else s

(* Parse a YAML inline list ["a","b"] into ["a";"b"]. Returns None if
   the surface syntax doesn't match the bracketed form. Tolerant of
   single quotes and unquoted bare tokens. *)
let parse_inline_list raw =
  let s = String.trim raw in
  let n = String.length s in
  if n < 2 || s.[0] <> '[' || s.[n-1] <> ']' then None
  else
    let inner = String.sub s 1 (n - 2) in
    let parts = String.split_on_char ',' inner in
    let xs = List.map unquote parts in
    let xs = List.filter (fun s -> s <> "") xs in
    if xs = [] then None else Some xs

(* Find a sub-block under a parent key in the YAML body. We look for
   the line ["<parent>:"] (no value) and collect subsequent more-indented
   lines into a sub-body. *)
let leading_spaces s =
  let n = String.length s in
  let rec go i =
    if i >= n then i
    else match s.[i] with ' ' -> go (i + 1) | _ -> i
  in
  go 0

let find_subblock body parent_key =
  let lines = split_lines body in
  let rec find_parent acc parent_indent = function
    | [] -> None
    | l :: rest ->
        let trimmed = String.trim l in
        if trimmed = parent_key ^ ":" then
          let indent = leading_spaces l in
          collect (List.rev acc) indent rest
        else find_parent (l :: acc) parent_indent rest
  and collect _outer parent_indent rest =
    let buf = Buffer.create 64 in
    let rec take = function
      | [] -> ()
      | l :: tail ->
          let il = leading_spaces l in
          let trimmed = String.trim l in
          if trimmed = "" then (Buffer.add_string buf l;
                                Buffer.add_char buf '\n'; take tail)
          else if il > parent_indent then
            (Buffer.add_string buf l;
             Buffer.add_char buf '\n'; take tail)
          else ()
    in
    take rest;
    Some (Buffer.contents buf)
  in
  find_parent [] 0 lines

let extract_verifier body =
  match find_subblock body "verifier" with
  | None -> None, None
  | Some sub ->
      let cmd = match find_field sub "command" with
        | Some raw -> parse_inline_list raw
        | None -> None
      in
      let to_s = int_field sub "timeout_s" in
      cmd, to_s

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
  let verifier_command, verifier_timeout_s = extract_verifier body in
  { version; cls; raw = body; after = close_at + 5;
    verifier_command; verifier_timeout_s }
