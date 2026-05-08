(** Internal: yojson encoders for [Characterization.t]. Hand-written
    (no ppx) so [Canonicalize] has full control over the wire shape.
    Decoders live in [Characterization_decoder]. *)

open Characterization

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

let stream_kind_to_yojson = function
  | `Text   -> yj_string "text"
  | `Binary -> yj_string "binary"
  | `None   -> yj_string "none"

let mode_to_yojson = function
  | `R  -> yj_string "r"
  | `W  -> yj_string "w"
  | `Rw -> yj_string "rw"

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

let to_yojson (c : t) : Yojson.Safe.t =
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
    "language", yj_string c.language;
    "verifier_command", yj_list yj_string c.verifier_command;
    "hash", yj_string c.hash;
  ]
