(** [Kb_regen] — see [kb_regen.mli]. *)

let target_files = [
  "INDEX.md";
  "GLOSSARY.md";
  "spec/data-model.md";
  "spec/algorithms.md";
  "properties/functional.md";
  "properties/edge-cases.md";
]

let aspects_for = function
  | "INDEX.md" ->
      [ "goal"; "inputs_outputs"; "errors"; "fs_contract";
        "examples_accept"; "examples_refuse"; "out_of_scope" ]
  | "GLOSSARY.md" -> [ "goal"; "examples_accept" ]
  | "spec/data-model.md" -> [ "inputs_outputs"; "errors"; "fs_contract" ]
  | "spec/algorithms.md" -> [ "examples_accept"; "examples_refuse" ]
  | "properties/functional.md" ->
      [ "goal"; "inputs_outputs"; "errors"; "fs_contract";
        "examples_accept"; "examples_refuse" ]
  | "properties/edge-cases.md" -> [ "examples_refuse" ]
  | _ -> []

let aspect_value (c : Characterization.t) = function
  | "goal" -> c.goal
  | "inputs_outputs" ->
      Canonical_json.to_string
        (Characterization_json.io_schema_to_yojson c.inputs_outputs)
  | "errors" ->
      Canonical_json.to_string
        (`List (List.map Characterization_json.error_entry_to_yojson
                  c.errors))
  | "fs_contract" ->
      Canonical_json.to_string
        (Characterization_json.fs_contract_to_yojson c.fs_contract)
  | "examples_accept" ->
      Canonical_json.to_string
        (`List (List.map Characterization_json.acceptance_example_to_yojson
                  c.examples_accept))
  | "examples_refuse" ->
      Canonical_json.to_string
        (`List (List.map Characterization_json.refusing_example_to_yojson
                  c.examples_refuse))
  | "out_of_scope" ->
      String.concat "," c.out_of_scope
  | _ -> ""

let all_aspect_names = [
  "goal"; "inputs_outputs"; "errors"; "fs_contract";
  "examples_accept"; "examples_refuse"; "out_of_scope";
]

let diff_aspects ~prev ~current =
  match prev with
  | None -> all_aspect_names
  | Some p ->
      List.filter (fun a ->
        aspect_value p a <> aspect_value current a) all_aspect_names

let files_affected_by ~changed =
  List.filter (fun f ->
    let aspects = aspects_for f in
    List.exists (fun a -> List.mem a aspects) changed
  ) target_files

(* --- ownership detection (P14, T18) --- *)

let extract_content_hash body =
  let lines = String.split_on_char '\n' body in
  let rec collect_fm = function
    | [] -> []
    | "---" :: rest ->
        let rec until_end acc = function
          | [] -> List.rev acc
          | "---" :: _ -> List.rev acc
          | l :: tl -> until_end (l :: acc) tl
        in
        until_end [] rest
    | _ :: tl -> collect_fm tl
  in
  let fm_lines = collect_fm lines in
  let prefix = "content_hash:" in
  List.find_map (fun l ->
    let l' = String.trim l in
    if String.length l' > String.length prefix
       && String.sub l' 0 (String.length prefix) = prefix then
      Some (String.trim
              (String.sub l' (String.length prefix)
                 (String.length l' - String.length prefix)))
    else None
  ) fm_lines

let body_after_frontmatter body =
  let lines = String.split_on_char '\n' body in
  let rec drop_fm seen = function
    | [] -> []
    | "---" :: rest when not seen -> drop_fm true rest
    | "---" :: rest when seen -> rest
    | _ :: rest when seen -> drop_fm seen rest
    | _ :: rest -> drop_fm seen rest
  in
  String.concat "\n" (drop_fm false lines)

let is_owned_by_k4k ~k4k_dir ~rel_path =
  let path = Filename.concat k4k_dir rel_path in
  if not (Sys.file_exists path) then true
  else
    let body = Persist.read_file path in
    match extract_content_hash body with
    | None -> false
    | Some recorded ->
        let actual =
          Persist.sha256_hex (body_after_frontmatter body) in
        String.equal recorded actual

let render_file = Kb_render.render_file

let write_one ~k4k_dir ~rel_path ~d ~logger =
  if is_owned_by_k4k ~k4k_dir ~rel_path then begin
    let path = Filename.concat k4k_dir rel_path in
    Persist.atomic_write ~path (Kb_render.render_file ~rel_path ~d);
    Logger.info logger "kb-regen.write"
      (`Assoc [ "file", `String rel_path ])
  end else
    Logger.info logger "ownership.flip"
      (`Assoc [ "file", `String rel_path ])

let regen_set ~k4k_dir ~current_d ~logger files =
  Logger.info logger "kb-regen.start"
    (`Assoc [ "files", `Int (List.length files) ]);
  List.iter (fun f -> write_one ~k4k_dir ~rel_path:f ~d:current_d ~logger)
    files;
  Logger.info logger "kb-regen.complete"
    (`Assoc [ "files", `Int (List.length files) ])

let regen ~k4k_dir ~prev_d ~current_d ~logger =
  let changed = diff_aspects ~prev:prev_d ~current:current_d in
  let files = files_affected_by ~changed in
  regen_set ~k4k_dir ~current_d ~logger files

let regen_full ~k4k_dir ~current_d ~logger =
  regen_set ~k4k_dir ~current_d ~logger target_files
