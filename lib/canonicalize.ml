(** Pure canonicalization of [Characterization.t] per
    [kb/spec/algorithms.md#canonicalize] and ADR-005. *)

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

let by_arg_name (a : Characterization.arg_spec) (b : Characterization.arg_spec) =
  String.compare a.name b.name

let by_err_id (a : Characterization.error_entry) (b : Characterization.error_entry) =
  String.compare a.id b.id

let by_glob (a : Characterization.path_pattern) (b : Characterization.path_pattern) =
  String.compare a.glob b.glob

let by_acc (a : Characterization.acceptance_example)
            (b : Characterization.acceptance_example) =
  String.compare a.name b.name

let by_ref (a : Characterization.refusing_example)
            (b : Characterization.refusing_example) =
  String.compare a.name b.name

let by_exit (a : Characterization.exit_code_entry)
             (b : Characterization.exit_code_entry) =
  Int.compare a.code b.code

(* --- per-field normalization --- *)

let n_arg (a : Characterization.arg_spec) : Characterization.arg_spec =
  { a with name = normalize_string a.name;
           type_ = normalize_string a.type_;
           doc = normalize_string a.doc }

let n_stream (s : Characterization.stream_spec) : Characterization.stream_spec =
  { s with doc = normalize_string s.doc;
           encoding = (match s.encoding with
                       | None -> None
                       | Some e -> Some (normalize_string e)) }

let n_exit (e : Characterization.exit_code_entry)
    : Characterization.exit_code_entry =
  { e with condition = normalize_string e.condition }

let n_err (e : Characterization.error_entry)
    : Characterization.error_entry =
  { e with id = normalize_string e.id;
           when_ = normalize_string e.when_;
           message_template = normalize_string e.message_template }

let n_glob (p : Characterization.path_pattern) : Characterization.path_pattern =
  { p with glob = normalize_string p.glob }

let n_snap (p : Characterization.path_snapshot)
    : Characterization.path_snapshot =
  { path = normalize_string p.path;
    sha256 = normalize_string p.sha256 }

let n_expect (e : Characterization.example_expect)
    : Characterization.example_expect =
  { e with stdout = normalize_string e.stdout;
           stderr = normalize_string e.stderr;
           fs_after = (match e.fs_after with
             | None -> None
             | Some xs -> Some (List.map n_snap xs)) }

let n_accept (a : Characterization.acceptance_example)
    : Characterization.acceptance_example =
  { name = normalize_string a.name;
    argv = List.map normalize_string a.argv;
    stdin = (match a.stdin with
             | None -> None
             | Some s -> Some (normalize_string s));
    expect = n_expect a.expect }

let n_refuse (r : Characterization.refusing_example)
    : Characterization.refusing_example =
  { name = normalize_string r.name;
    argv = List.map normalize_string r.argv;
    stdin = (match r.stdin with
             | None -> None
             | Some s -> Some (normalize_string s));
    expect_error = normalize_string r.expect_error }

let n_io (io : Characterization.io_schema) : Characterization.io_schema =
  { argv = List.sort by_arg_name (List.map n_arg io.argv);
    stdin = n_stream io.stdin;
    stdout = n_stream io.stdout;
    stderr = n_stream io.stderr;
    exit_codes = List.sort by_exit (List.map n_exit io.exit_codes); }

let n_fs (f : Characterization.fs_contract) : Characterization.fs_contract =
  { reads = List.sort by_glob (List.map n_glob f.reads);
    writes = List.sort by_glob (List.map n_glob f.writes);
    creates = List.sort by_glob (List.map n_glob f.creates); }

let pre_canonical (c : Characterization.t) : Characterization.t =
  { cls = normalize_string c.cls;
    goal = normalize_string c.goal;
    inputs_outputs = n_io c.inputs_outputs;
    errors = List.sort by_err_id (List.map n_err c.errors);
    fs_contract = n_fs c.fs_contract;
    concurrency = normalize_string c.concurrency;
    perf = normalize_string c.perf;
    examples_accept = List.sort by_acc (List.map n_accept c.examples_accept);
    examples_refuse = List.sort by_ref (List.map n_refuse c.examples_refuse);
    out_of_scope = List.map normalize_string c.out_of_scope;
    verifier_pref = (match c.verifier_pref with
                     | None -> None
                     | Some s -> Some (normalize_string s));
    language = normalize_string c.language;
    verifier_command = List.map normalize_string c.verifier_command;
    hash = ""; }

let canonicalize (c : Characterization.t) : Characterization.t =
  let pre = pre_canonical c in
  let bytes = Canonical_json.to_string (Characterization_json.to_yojson pre) in
  { pre with hash = Persist.sha256_hex bytes }

let canonical_bytes (c : Characterization.t) : string =
  let zeroed = { c with hash = "" } in
  Canonical_json.to_string (Characterization_json.to_yojson zeroed)

let canonical_json_string = Canonical_json.to_string

let equal a b =
  String.equal a.Characterization.hash b.Characterization.hash
