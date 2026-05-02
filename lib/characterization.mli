(** [Characterization] — formal AST per [kb/spec/data-model.md].

    This module is responsible for the in-memory shape of the desired and
    current characterizations and their JSON round-trip. It implements the
    schema half of P2/P4: every two equivalent ASTs (after canonicalization)
    serialize to the same canonical bytes.

    Key design decisions: hand-written to_/of_yojson (no ppx) to keep
    full control over canonical-JSON formatting; the [hash] field is
    populated by [Canonicalize.canonicalize], not by this module. *)

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

type exit_code_entry = { code : int; condition : string }

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

type path_pattern = { glob : string; mode : [ `R | `W | `Rw ] }
type fs_contract = {
  reads   : path_pattern list;
  writes  : path_pattern list;
  creates : path_pattern list;
}

type path_snapshot = { path : string; sha256 : string }

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

(** [to_yojson t] serializes to a yojson tree. The output is *not*
    canonical-JSON; use [Canonicalize] to produce a canonical form. *)
val to_yojson : t -> Yojson.Safe.t

(** [of_yojson v] parses a yojson tree into a Characterization.

    @raise Error.K4k_error E_format on malformed input.
    @invariant P4 — preserves field bytes verbatim (no normalization
                    happens here). *)
val of_yojson : Yojson.Safe.t -> t

(** [empty] — a minimal structurally-valid baseline. *)
val empty : t
