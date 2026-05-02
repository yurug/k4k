(** [Characterization] — pure types per [kb/spec/data-model.md].

    Encoders/decoders live in [Characterization_json] (this keeps every
    file under the 200-line cap from [conventions/code-style.md]). *)

type stream_kind = [ `Text | `Binary | `None ]

type stream_spec = {
  kind     : stream_kind;
  encoding : string option;
  doc      : string;
}

type arg_kind = [ `Flag | `Option | `Positional ]

type arg_spec = {
  name     : string;
  kind     : arg_kind;
  type_    : string;
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
  expect_error : string;
}

type t = {
  cls             : string;
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
  hash            : string;
}

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
