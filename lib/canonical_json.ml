(** Canonical JSON serialization per ADR-005. Object keys lex-sorted; no
    whitespace between tokens; non-ASCII code points escaped as
    [\uXXXX]. *)

let buf_add_escape buf c =
  match c with
  | '"'  -> Buffer.add_string buf "\\\""
  | '\\' -> Buffer.add_string buf "\\\\"
  | '\b' -> Buffer.add_string buf "\\b"
  | '\012' -> Buffer.add_string buf "\\f"
  | '\n' -> Buffer.add_string buf "\\n"
  | '\r' -> Buffer.add_string buf "\\r"
  | '\t' -> Buffer.add_string buf "\\t"
  | c when Char.code c < 0x20 ->
      Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
  | c when Char.code c < 0x7f -> Buffer.add_char buf c
  | c -> Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))

let buf_add_string buf s =
  Buffer.add_char buf '"';
  String.iter (buf_add_escape buf) s;
  Buffer.add_char buf '"'

let rec emit buf (v : Yojson.Safe.t) =
  match v with
  | `Null -> Buffer.add_string buf "null"
  | `Bool true -> Buffer.add_string buf "true"
  | `Bool false -> Buffer.add_string buf "false"
  | `Int i -> Buffer.add_string buf (string_of_int i)
  | `Intlit s -> Buffer.add_string buf s
  | `Float f -> Buffer.add_string buf (Printf.sprintf "%.17g" f)
  | `String s -> buf_add_string buf s
  | `Assoc fs ->
      let fs = List.sort (fun (a, _) (b, _) -> String.compare a b) fs in
      Buffer.add_char buf '{';
      List.iteri (fun i (k, v) ->
        if i > 0 then Buffer.add_char buf ',';
        buf_add_string buf k;
        Buffer.add_char buf ':';
        emit buf v
      ) fs;
      Buffer.add_char buf '}'
  | `List xs ->
      Buffer.add_char buf '[';
      List.iteri (fun i v ->
        if i > 0 then Buffer.add_char buf ',';
        emit buf v
      ) xs;
      Buffer.add_char buf ']'

let to_string v =
  let buf = Buffer.create 256 in
  emit buf v;
  Buffer.contents buf
