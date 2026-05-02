(** [Characterization] — the formal AST per [kb/spec/data-model.md].

    Pure data + JSON round-trip. No I/O. No canonicalization (lives in
    [Canonicalize]). [hash] is filled in by [Canonicalize]. *)

type stream_kind = [ `Text | `Binary | `None ]

type stream_spec = {
  kind     : stream_kind;
  encoding : string option;     (* "utf-8" or [None] *)
  doc      : string;
}

type arg_kind = [ `Flag | `Option | `Positional ]

type arg_spec = {
  name     : string;
  kind     : arg_kind;
  type_    : string;            (* "string"|"int"|"bool" *)
  required : bool;
  repeats  : bool;
  doc      : string;
}

type exit_code_entry = {
  code      : int;
  condition : string;
}

type io_schema = {
  argv       : arg_spec list;
  stdin      : stream_spec;
  stdout     : stream_spec;
  stderr     : stream_spec;
  exit_codes : exit_code_entry list;
}

type error_entry = {
  id               : string;
  when_            : string;
  message_template : string;
  exit_code        : int;
}

type path_pattern = {
  glob : string;
  mode : [ `R | `W | `Rw ];
}

type fs_contract = {
  reads   : path_pattern list;
  writes  : path_pattern list;
  creates : path_pattern list;
}

type path_snapshot = {
  path   : string;
  sha256 : string;
}

type example_expect = {
  stdout    : string;
  stderr    : string;
  exit_code : int;
  fs_after  : path_snapshot list option;
}

type acceptance_example = {
  name   : string;
  argv   : string list;
  stdin  : string option;
  expect : example_expect;
}

type refusing_example = {
  name         : string;
  argv         : string list;
  stdin        : string option;
  expect_error : string;        (* matches an [error_entry.id] *)
}

type t = {
  cls             : string;     (* "cli" *)
  goal            : string;
  inputs_outputs  : io_schema;
  errors          : error_entry list;
  fs_contract     : fs_contract;
  concurrency     : string;
  perf            : string;
  examples_accept : acceptance_example list;
  examples_refuse : refusing_example list;
  out_of_scope    : string list;
  verifier_pref   : string option;
  hash            : string;     (* set by [Canonicalize.canonicalize] *)
}

(* --- Yojson encoders / decoders (hand-written; no ppx). --- *)

let yj_string s : Yojson.Safe.t = `String s
let yj_int i : Yojson.Safe.t = `Int i
let yj_bool b : Yojson.Safe.t = `Bool b
let yj_list f xs : Yojson.Safe.t = `List (List.map f xs)
let yj_opt_string = function None -> `Null | Some s -> `String s
let yj_opt_list f = function None -> `Null | Some xs -> yj_list f xs

let arg_kind_to_yojson = function
  | `Flag       -> yj_string "flag"
  | `Option     -> yj_string "option"
  | `Positional -> yj_string "positional"

let arg_kind_of_string = function
  | "flag"       -> `Flag
  | "option"     -> `Option
  | "positional" -> `Positional
  | _            -> `Positional

let stream_kind_to_yojson = function
  | `Text   -> yj_string "text"
  | `Binary -> yj_string "binary"
  | `None   -> yj_string "none"

let stream_kind_of_string = function
  | "text"   -> `Text
  | "binary" -> `Binary
  | "none"   -> `None
  | _        -> `Text

let mode_to_yojson = function
  | `R  -> yj_string "r"
  | `W  -> yj_string "w"
  | `Rw -> yj_string "rw"

let mode_of_string = function
  | "r"  -> `R
  | "w"  -> `W
  | "rw" -> `Rw
  | _    -> `R

let arg_spec_to_yojson (a : arg_spec) : Yojson.Safe.t =
  `Assoc [
    "name", yj_string a.name;
    "kind", arg_kind_to_yojson a.kind;
    "type", yj_string a.type_;
    "required", yj_bool a.required;
    "repeats", yj_bool a.repeats;
    "doc", yj_string a.doc;
  ]

let stream_spec_to_yojson (s : stream_spec) : Yojson.Safe.t =
  `Assoc [
    "type", stream_kind_to_yojson s.kind;
    "encoding",
      (match s.encoding with None -> `Null | Some e -> yj_string e);
    "doc", yj_string s.doc;
  ]

let exit_code_entry_to_yojson (e : exit_code_entry) : Yojson.Safe.t =
  `Assoc [ "code", yj_int e.code; "condition", yj_string e.condition ]

let io_schema_to_yojson (io : io_schema) : Yojson.Safe.t =
  `Assoc [
    "argv", yj_list arg_spec_to_yojson io.argv;
    "stdin", stream_spec_to_yojson io.stdin;
    "stdout", stream_spec_to_yojson io.stdout;
    "stderr", stream_spec_to_yojson io.stderr;
    "exit_codes", yj_list exit_code_entry_to_yojson io.exit_codes;
  ]

let error_entry_to_yojson (e : error_entry) : Yojson.Safe.t =
  `Assoc [
    "id", yj_string e.id;
    "when", yj_string e.when_;
    "message_template", yj_string e.message_template;
    "exit_code", yj_int e.exit_code;
  ]

let path_pattern_to_yojson (p : path_pattern) : Yojson.Safe.t =
  `Assoc [ "glob", yj_string p.glob; "mode", mode_to_yojson p.mode ]

let fs_contract_to_yojson (f : fs_contract) : Yojson.Safe.t =
  `Assoc [
    "reads",   yj_list path_pattern_to_yojson f.reads;
    "writes",  yj_list path_pattern_to_yojson f.writes;
    "creates", yj_list path_pattern_to_yojson f.creates;
  ]

let path_snapshot_to_yojson (p : path_snapshot) : Yojson.Safe.t =
  `Assoc [ "path", yj_string p.path; "sha256", yj_string p.sha256 ]

let example_expect_to_yojson (e : example_expect) : Yojson.Safe.t =
  `Assoc [
    "stdout", yj_string e.stdout;
    "stderr", yj_string e.stderr;
    "exit_code", yj_int e.exit_code;
    "fs_after", yj_opt_list path_snapshot_to_yojson e.fs_after;
  ]

let acceptance_example_to_yojson (a : acceptance_example) : Yojson.Safe.t =
  `Assoc [
    "name", yj_string a.name;
    "argv", yj_list yj_string a.argv;
    "stdin", yj_opt_string a.stdin;
    "expect", example_expect_to_yojson a.expect;
  ]

let refusing_example_to_yojson (r : refusing_example) : Yojson.Safe.t =
  `Assoc [
    "name", yj_string r.name;
    "argv", yj_list yj_string r.argv;
    "stdin", yj_opt_string r.stdin;
    "expect_error", yj_string r.expect_error;
  ]

let to_yojson c : Yojson.Safe.t =
  `Assoc [
    "class", yj_string c.cls;
    "goal", yj_string c.goal;
    "inputs_outputs", io_schema_to_yojson c.inputs_outputs;
    "errors", yj_list error_entry_to_yojson c.errors;
    "fs_contract", fs_contract_to_yojson c.fs_contract;
    "concurrency", yj_string c.concurrency;
    "perf", yj_string c.perf;
    "examples_accept", yj_list acceptance_example_to_yojson c.examples_accept;
    "examples_refuse", yj_list refusing_example_to_yojson c.examples_refuse;
    "out_of_scope", yj_list yj_string c.out_of_scope;
    "verifier_pref", yj_opt_string c.verifier_pref;
    "hash", yj_string c.hash;
  ]

(* --- Decoders. Strict enough for the canonical JSON we emit; permissive
   enough to accept agent output that Yojson can parse. --- *)

let parse_error msg = raise (Error.K4k_error (Error.E_format
  { line = 0; col = 0; reason = msg }))

let assoc_of = function
  | `Assoc fs -> fs
  | _ -> parse_error "expected JSON object"

let lookup ?(default=`Null) k fs =
  try List.assoc k fs with Not_found -> default

let str_of = function `String s -> s | _ -> parse_error "expected string"
let int_of = function `Int i -> i | _ -> parse_error "expected int"
let bool_of = function `Bool b -> b | _ -> parse_error "expected bool"
let list_of = function `List xs -> xs | _ -> parse_error "expected list"

let opt_str = function `Null -> None | `String s -> Some s
                     | _ -> parse_error "expected string or null"

let opt_list f = function
  | `Null -> None
  | `List xs -> Some (List.map f xs)
  | _ -> parse_error "expected list or null"

let arg_spec_of_yojson v =
  let fs = assoc_of v in
  { name = str_of (lookup "name" fs);
    kind = arg_kind_of_string (str_of (lookup "kind" fs));
    type_ = str_of (lookup "type" fs);
    required = bool_of (lookup "required" fs);
    repeats = bool_of (lookup "repeats" fs);
    doc = str_of (lookup ~default:(`String "") "doc" fs);
  }

let stream_spec_of_yojson v =
  let fs = assoc_of v in
  { kind = stream_kind_of_string (str_of (lookup "type" fs));
    encoding = opt_str (lookup "encoding" fs);
    doc = str_of (lookup ~default:(`String "") "doc" fs);
  }

let exit_code_entry_of_yojson v =
  let fs = assoc_of v in
  { code = int_of (lookup "code" fs);
    condition = str_of (lookup "condition" fs); }

let io_schema_of_yojson v =
  let fs = assoc_of v in
  { argv = List.map arg_spec_of_yojson (list_of (lookup "argv" fs));
    stdin = stream_spec_of_yojson (lookup "stdin" fs);
    stdout = stream_spec_of_yojson (lookup "stdout" fs);
    stderr = stream_spec_of_yojson (lookup "stderr" fs);
    exit_codes = List.map exit_code_entry_of_yojson
                   (list_of (lookup "exit_codes" fs));
  }

let error_entry_of_yojson v =
  let fs = assoc_of v in
  { id = str_of (lookup "id" fs);
    when_ = str_of (lookup "when" fs);
    message_template = str_of (lookup "message_template" fs);
    exit_code = int_of (lookup "exit_code" fs);
  }

let path_pattern_of_yojson v =
  let fs = assoc_of v in
  { glob = str_of (lookup "glob" fs);
    mode = mode_of_string (str_of (lookup "mode" fs));
  }

let fs_contract_of_yojson v =
  let fs = assoc_of v in
  { reads = List.map path_pattern_of_yojson (list_of (lookup "reads" fs));
    writes = List.map path_pattern_of_yojson (list_of (lookup "writes" fs));
    creates = List.map path_pattern_of_yojson (list_of (lookup "creates" fs));
  }

let path_snapshot_of_yojson v =
  let fs = assoc_of v in
  { path = str_of (lookup "path" fs);
    sha256 = str_of (lookup "sha256" fs);
  }

let example_expect_of_yojson v =
  let fs = assoc_of v in
  { stdout = str_of (lookup ~default:(`String "") "stdout" fs);
    stderr = str_of (lookup ~default:(`String "") "stderr" fs);
    exit_code = int_of (lookup "exit_code" fs);
    fs_after = opt_list path_snapshot_of_yojson (lookup "fs_after" fs);
  }

let acceptance_example_of_yojson v =
  let fs = assoc_of v in
  { name = str_of (lookup "name" fs);
    argv = List.map str_of (list_of (lookup "argv" fs));
    stdin = opt_str (lookup "stdin" fs);
    expect = example_expect_of_yojson (lookup "expect" fs);
  }

let refusing_example_of_yojson v =
  let fs = assoc_of v in
  { name = str_of (lookup "name" fs);
    argv = List.map str_of (list_of (lookup "argv" fs));
    stdin = opt_str (lookup "stdin" fs);
    expect_error = str_of (lookup "expect_error" fs);
  }

let of_yojson v =
  let fs = assoc_of v in
  { cls = str_of (lookup ~default:(`String "cli") "class" fs);
    goal = str_of (lookup ~default:(`String "") "goal" fs);
    inputs_outputs = io_schema_of_yojson (lookup "inputs_outputs" fs);
    errors = List.map error_entry_of_yojson
               (list_of (lookup ~default:(`List []) "errors" fs));
    fs_contract = fs_contract_of_yojson (lookup "fs_contract" fs);
    concurrency = str_of (lookup ~default:(`String "N/A") "concurrency" fs);
    perf = str_of (lookup ~default:(`String "N/A") "perf" fs);
    examples_accept = List.map acceptance_example_of_yojson
                        (list_of (lookup ~default:(`List []) "examples_accept" fs));
    examples_refuse = List.map refusing_example_of_yojson
                        (list_of (lookup ~default:(`List []) "examples_refuse" fs));
    out_of_scope = List.map str_of
                     (list_of (lookup ~default:(`List []) "out_of_scope" fs));
    verifier_pref = opt_str (lookup "verifier_pref" fs);
    hash = str_of (lookup ~default:(`String "") "hash" fs);
  }

(** A minimal, structurally-valid empty characterization. Useful in tests
    and as the "no-op" baseline when stitching test cases. *)
let empty : t = {
  cls = "cli";
  goal = "";
  inputs_outputs = {
    argv = [];
    stdin = { kind = `None; encoding = None; doc = "" };
    stdout = { kind = `Text; encoding = Some "utf-8"; doc = "" };
    stderr = { kind = `Text; encoding = Some "utf-8"; doc = "" };
    exit_codes = [];
  };
  errors = [];
  fs_contract = { reads = []; writes = []; creates = [] };
  concurrency = "N/A";
  perf = "N/A";
  examples_accept = [];
  examples_refuse = [];
  out_of_scope = [];
  verifier_pref = None;
  hash = "";
}
