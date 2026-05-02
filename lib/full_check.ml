(** Step-2 entry point: structural + semantic stability + persistence.

    Closes over a chosen [Agent_backend.S] module + value (so the
    harness functor can stay pure on signatures). *)

let render_prompt parsed =
  let user_sections = Stability.render_user_sections parsed in
  Prompts.render "formalize.md"
    [ "user_sections", user_sections;
      "example_input", "";
      "example_output", "" ]

let mirror_md (d : Characterization.t) =
  Printf.sprintf
    "---\nowner: k4k\ncontent_hash: %s\n---\n# Desired Characterization\n\n\
     Goal: %s\n\nClass: %s\n"
    d.hash d.goal d.cls

let persist_desired ~k4k_dir d =
  let bytes = Canonical_json.to_string
                (Characterization_json.to_yojson d) in
  Persist.write_desired ~k4k_dir ~bytes ~mirror_md:(mirror_md d)

let manifest_json ~file_path ~file_content ~user_h
    ~agent_name ~agent_version ~verifier_name ~desired_hash =
  Manifest.build
    ~file_path ~file_sha256:(Persist.sha256_hex file_content)
    ~user_section_hashes:user_h
    ~agent_name ~agent_version
    ~verifier_name ~verifier_version:"0.1.0-stub"
    ~desired_hash ()

let load_cached_desired ~k4k_dir ~hash =
  match hash with
  | None -> None
  | Some _ ->
      let p = Filename.concat k4k_dir "characterization/desired/spec.json" in
      if not (Sys.file_exists p) then None
      else
        try
          let raw = Persist.read_file p in
          let parsed = Yojson.Safe.from_string raw in
          let c = Characterization_decoder.of_yojson parsed in
          Some (Canonicalize.canonicalize c)
        with _ -> None

let raise_unstable issues =
  raise (Error.K4k_error (Error.E_unstable issues))

let read_or_raise path =
  if not (Sys.file_exists path) then
    raise (Error.K4k_error (Error.E_file_not_found path));
  Persist.read_file path

let do_structural ~logger parsed =
  match Stability.check_structural parsed with
  | Stability.Unstable issues ->
      Logger.info logger "stability.fail"
        (`Assoc [ "kind", `String "structural";
                  "issue_count", `Int (List.length issues) ]);
      raise_unstable issues
  | Stability.Stable -> ()

let persist_pass ~inputs ~content ~parsed ~agent_name ~agent_version
    ~verifier_name (d : Characterization.t) =
  persist_desired ~k4k_dir:inputs.Harness.k4k_dir d;
  let user_h = Stability.user_section_hashes parsed in
  let mj = manifest_json
    ~file_path:inputs.file_path ~file_content:content ~user_h
    ~agent_name ~agent_version ~verifier_name ~desired_hash:d.hash in
  Persist.atomic_write
    ~path:(Filename.concat inputs.k4k_dir "manifest.json")
    (Yojson.Safe.pretty_to_string ~std:true mj)

let handle_outcome ~inputs ~content ~parsed
    ~agent_name ~agent_version ~verifier_name (outcome : Stability.semantic_outcome) =
  match outcome with
  | Sem_cached d ->
      Logger.info inputs.Harness.logger "stability.pass"
        (`Assoc [ "cached", `Bool true; "hash", `String d.hash ]);
      d
  | Sem_stable (d, _) ->
      let cov = Coverage.check d in
      if cov <> [] then begin
        Logger.info inputs.logger "stability.fail"
          (`Assoc [ "kind", `String "coverage";
                    "issue_count", `Int (List.length cov) ]);
        raise_unstable cov
      end;
      persist_pass ~inputs ~content ~parsed
        ~agent_name ~agent_version ~verifier_name d;
      Logger.info inputs.logger "stability.pass"
        (`Assoc [ "hash", `String d.hash ]);
      d
  | Sem_unstable (issues, _) ->
      Logger.info inputs.logger "stability.fail"
        (`Assoc [ "kind", `String "formalization";
                  "issue_count", `Int (List.length issues) ]);
      raise_unstable issues

let run (type b)
    (module B : Agent_backend.S with type t = b)
    (module V : Verifier.S)
    ~(backend : b) ~(inputs : Harness.check_inputs) =
  Persist.ensure_dir inputs.k4k_dir;
  let manifest = Manifest.read_or_init ~k4k_dir:inputs.k4k_dir in
  let content = read_or_raise inputs.file_path in
  Logger.info inputs.logger "stability.start"
    (`Assoc [ "file", `String inputs.file_path ]);
  let parsed = Parser.parse content in
  do_structural ~logger:inputs.logger parsed;
  let prev_h = Manifest.user_section_hashes manifest in
  let user_h = Stability.user_section_hashes parsed in
  let cached_d = load_cached_desired ~k4k_dir:inputs.k4k_dir
                   ~hash:(Manifest.desired_hash manifest) in
  let invoker = {
    Stability.bk = backend;
    invoke = (fun ~purpose ~prompt ~budget ->
      B.invoke backend ~purpose ~prompt ~budget);
  } in
  let outcome =
    Stability.semantic_check_with_backend
      ~k4k_dir:inputs.k4k_dir ~prompt:(render_prompt parsed) ~budget:1000
      ~prev_hashes:prev_h ~current_hashes:user_h
      ~cached_desired:cached_d invoker
  in
  handle_outcome ~inputs ~content ~parsed
    ~agent_name:B.name ~agent_version:(B.version backend)
    ~verifier_name:V.name outcome
