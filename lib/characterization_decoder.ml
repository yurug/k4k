(** Internal: yojson decoder for [Characterization.t]. Strict shape, but
    forgiving on optional fields. Permissive whitespace cleanup happens
    in [Permissive_json] *before* this decoder runs. *)

open Characterization

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

let arg_kind_of_string = function
  | "flag"       -> `Flag
  | "option"     -> `Option
  | "positional" -> `Positional
  | _            -> `Positional

let stream_kind_of_string = function
  | "text"   -> `Text
  | "binary" -> `Binary
  | "none"   -> `None
  | _        -> `Text

let mode_of_string = function
  | "r"  -> `R
  | "w"  -> `W
  | "rw" -> `Rw
  | _    -> `R

let arg_spec_of_yojson v : arg_spec =
  let fs = assoc_of v in
  { name = str_of (lookup "name" fs);
    kind = arg_kind_of_string (str_of (lookup "kind" fs));
    type_ = str_of (lookup "type" fs);
    required = bool_of (lookup "required" fs);
    repeats = bool_of (lookup "repeats" fs);
    doc = str_of (lookup ~default:(`String "") "doc" fs);
  }

let stream_spec_of_yojson v : stream_spec =
  let fs = assoc_of v in
  { kind = stream_kind_of_string (str_of (lookup "type" fs));
    encoding = opt_str (lookup "encoding" fs);
    doc = str_of (lookup ~default:(`String "") "doc" fs);
  }

let exit_code_entry_of_yojson v : exit_code_entry =
  let fs = assoc_of v in
  { code = int_of (lookup "code" fs);
    condition = str_of (lookup "condition" fs); }

let io_schema_of_yojson v : io_schema =
  let fs = assoc_of v in
  { argv = List.map arg_spec_of_yojson (list_of (lookup "argv" fs));
    stdin = stream_spec_of_yojson (lookup "stdin" fs);
    stdout = stream_spec_of_yojson (lookup "stdout" fs);
    stderr = stream_spec_of_yojson (lookup "stderr" fs);
    exit_codes = List.map exit_code_entry_of_yojson
                   (list_of (lookup "exit_codes" fs));
  }

let error_entry_of_yojson v : error_entry =
  let fs = assoc_of v in
  { id = str_of (lookup "id" fs);
    when_ = str_of (lookup "when" fs);
    message_template = str_of (lookup "message_template" fs);
    exit_code = int_of (lookup "exit_code" fs);
  }

let path_pattern_of_yojson v : path_pattern =
  let fs = assoc_of v in
  { glob = str_of (lookup "glob" fs);
    mode = mode_of_string (str_of (lookup "mode" fs));
  }

let fs_contract_of_yojson v : fs_contract =
  let fs = assoc_of v in
  { reads = List.map path_pattern_of_yojson (list_of (lookup "reads" fs));
    writes = List.map path_pattern_of_yojson (list_of (lookup "writes" fs));
    creates = List.map path_pattern_of_yojson (list_of (lookup "creates" fs));
  }

let path_snapshot_of_yojson v : path_snapshot =
  let fs = assoc_of v in
  { path = str_of (lookup "path" fs);
    sha256 = str_of (lookup "sha256" fs);
  }

let example_expect_of_yojson v : example_expect =
  let fs = assoc_of v in
  { stdout = str_of (lookup ~default:(`String "") "stdout" fs);
    stderr = str_of (lookup ~default:(`String "") "stderr" fs);
    exit_code = int_of (lookup "exit_code" fs);
    fs_after = opt_list path_snapshot_of_yojson (lookup "fs_after" fs);
  }

let acceptance_example_of_yojson v : acceptance_example =
  let fs = assoc_of v in
  { name = str_of (lookup "name" fs);
    argv = List.map str_of (list_of (lookup "argv" fs));
    stdin = opt_str (lookup "stdin" fs);
    expect = example_expect_of_yojson (lookup "expect" fs);
  }

let refusing_example_of_yojson v : refusing_example =
  let fs = assoc_of v in
  { name = str_of (lookup "name" fs);
    argv = List.map str_of (list_of (lookup "argv" fs));
    stdin = opt_str (lookup "stdin" fs);
    expect_error = str_of (lookup "expect_error" fs);
  }

let of_yojson v : t =
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
    language = str_of (lookup ~default:(`String "") "language" fs);
    verifier_command =
      (match lookup ~default:(`List []) "verifier_command" fs with
       | `List xs -> List.map str_of xs
       | _ -> parse_error "expected list for verifier_command");
    hash = str_of (lookup ~default:(`String "") "hash" fs);
  }
