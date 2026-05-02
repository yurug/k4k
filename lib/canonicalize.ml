(** Pure canonicalization of [Characterization.t] per
    [kb/spec/algorithms.md#canonicalize] and ADR-005. *)

(* --- whitespace --- *)

let is_ws = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false

let squeeze_ws s =
  let len = String.length s in
  let buf = Buffer.create len in
  let in_ws = ref false in
  let started = ref false in
  for i = 0 to len - 1 do
    let c = s.[i] in
    if is_ws c then in_ws := true
    else begin
      if !in_ws && !started then Buffer.add_char buf ' ';
      Buffer.add_char buf c;
      in_ws := false;
      started := true
    end
  done;
  Buffer.contents buf

let normalize_string = squeeze_ws

(* --- sort helpers --- *)

let by_name (a : Characterization.arg_spec) (b : Characterization.arg_spec) =
  String.compare a.name b.name

let by_error_id (a : Characterization.error_entry) (b : Characterization.error_entry) =
  String.compare a.id b.id

let by_glob (a : Characterization.path_pattern) (b : Characterization.path_pattern) =
  String.compare a.glob b.glob

let by_accept_name (a : Characterization.acceptance_example)
                    (b : Characterization.acceptance_example) =
  String.compare a.name b.name

let by_refuse_name (a : Characterization.refusing_example)
                    (b : Characterization.refusing_example) =
  String.compare a.name b.name

let by_exit_code (a : Characterization.exit_code_entry)
                  (b : Characterization.exit_code_entry) =
  Int.compare a.code b.code

(* --- per-field normalization --- *)

let normalize_arg (a : Characterization.arg_spec) : Characterization.arg_spec =
  { a with
    name = normalize_string a.name;
    type_ = normalize_string a.type_;
    doc = normalize_string a.doc }

let normalize_stream (s : Characterization.stream_spec) : Characterization.stream_spec =
  { s with doc = normalize_string s.doc;
           encoding = (match s.encoding with
                       | None -> None
                       | Some e -> Some (normalize_string e)) }

let normalize_exit_code (e : Characterization.exit_code_entry)
    : Characterization.exit_code_entry =
  { e with condition = normalize_string e.condition }

let normalize_error (e : Characterization.error_entry)
    : Characterization.error_entry =
  { e with id = normalize_string e.id;
           when_ = normalize_string e.when_;
           message_template = normalize_string e.message_template }

let normalize_path_pattern (p : Characterization.path_pattern)
    : Characterization.path_pattern =
  { p with glob = normalize_string p.glob }

let normalize_path_snapshot (p : Characterization.path_snapshot)
    : Characterization.path_snapshot =
  { path = normalize_string p.path;
    sha256 = normalize_string p.sha256 }

let normalize_example_expect (e : Characterization.example_expect)
    : Characterization.example_expect =
  { e with stdout = normalize_string e.stdout;
           stderr = normalize_string e.stderr;
           fs_after = (match e.fs_after with
             | None -> None
             | Some xs -> Some (List.map normalize_path_snapshot xs))
         }

let normalize_accept (a : Characterization.acceptance_example)
    : Characterization.acceptance_example =
  { name = normalize_string a.name;
    argv = List.map normalize_string a.argv;
    stdin = (match a.stdin with
             | None -> None
             | Some s -> Some (normalize_string s));
    expect = normalize_example_expect a.expect }

let normalize_refuse (r : Characterization.refusing_example)
    : Characterization.refusing_example =
  { name = normalize_string r.name;
    argv = List.map normalize_string r.argv;
    stdin = (match r.stdin with
             | None -> None
             | Some s -> Some (normalize_string s));
    expect_error = normalize_string r.expect_error }

let normalize_io (io : Characterization.io_schema) : Characterization.io_schema =
  { argv = List.sort by_name (List.map normalize_arg io.argv);
    stdin = normalize_stream io.stdin;
    stdout = normalize_stream io.stdout;
    stderr = normalize_stream io.stderr;
    exit_codes = List.sort by_exit_code
                   (List.map normalize_exit_code io.exit_codes); }

let normalize_fs (f : Characterization.fs_contract) : Characterization.fs_contract =
  { reads = List.sort by_glob (List.map normalize_path_pattern f.reads);
    writes = List.sort by_glob (List.map normalize_path_pattern f.writes);
    creates = List.sort by_glob (List.map normalize_path_pattern f.creates); }

(* --- canonical JSON printer (object-key-sorted, no whitespace, ASCII) --- *)

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
      Buffer.add_string buf
        (Printf.sprintf "\\u%04x" (Char.code c))
  | c when Char.code c < 0x7f -> Buffer.add_char buf c
  | c -> Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))

let buf_add_string buf s =
  Buffer.add_char buf '"';
  String.iter (buf_add_escape buf) s;
  Buffer.add_char buf '"'

let rec canonical_json buf (v : Yojson.Safe.t) =
  match v with
  | `Null -> Buffer.add_string buf "null"
  | `Bool true -> Buffer.add_string buf "true"
  | `Bool false -> Buffer.add_string buf "false"
  | `Int i -> Buffer.add_string buf (string_of_int i)
  | `Intlit s -> Buffer.add_string buf s
  | `Float f ->
      let s = Printf.sprintf "%.17g" f in
      Buffer.add_string buf s
  | `String s -> buf_add_string buf s
  | `Assoc fs ->
      let fs = List.sort (fun (a, _) (b, _) -> String.compare a b) fs in
      Buffer.add_char buf '{';
      List.iteri (fun i (k, v) ->
        if i > 0 then Buffer.add_char buf ',';
        buf_add_string buf k;
        Buffer.add_char buf ':';
        canonical_json buf v
      ) fs;
      Buffer.add_char buf '}'
  | `List xs ->
      Buffer.add_char buf '[';
      List.iteri (fun i v ->
        if i > 0 then Buffer.add_char buf ',';
        canonical_json buf v
      ) xs;
      Buffer.add_char buf ']'

let canonical_json_string v =
  let buf = Buffer.create 256 in
  canonical_json buf v;
  Buffer.contents buf

(* --- the main entry point --- *)

let canonicalize (c : Characterization.t) : Characterization.t =
  (* Pre-canonical (hash field zeroed, content normalized + sorted). *)
  let pre : Characterization.t = {
    cls = normalize_string c.cls;
    goal = normalize_string c.goal;
    inputs_outputs = normalize_io c.inputs_outputs;
    errors = List.sort by_error_id (List.map normalize_error c.errors);
    fs_contract = normalize_fs c.fs_contract;
    concurrency = normalize_string c.concurrency;
    perf = normalize_string c.perf;
    examples_accept = List.sort by_accept_name
                        (List.map normalize_accept c.examples_accept);
    examples_refuse = List.sort by_refuse_name
                        (List.map normalize_refuse c.examples_refuse);
    out_of_scope = List.map normalize_string c.out_of_scope;
    verifier_pref = (match c.verifier_pref with
                     | None -> None
                     | Some s -> Some (normalize_string s));
    hash = "";  (* zeroed; we hash without it. *)
  } in
  let canonical_bytes = canonical_json_string (Characterization.to_yojson pre) in
  let h = Persist.sha256_hex canonical_bytes in
  { pre with hash = h }

let canonical_bytes (c : Characterization.t) : string =
  let zeroed = { c with hash = "" } in
  canonical_json_string (Characterization.to_yojson zeroed)

let equal a b =
  String.equal a.Characterization.hash b.Characterization.hash
