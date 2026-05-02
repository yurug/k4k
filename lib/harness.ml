type check_inputs = {
  file_path : string;
  k4k_dir   : string;
  logger    : Logger.t;
}

type check_outcome =
  | Stable_structural
  | Unstable

module type S = sig
  val check : check_inputs -> check_outcome
end

let k4k_version_string = "0.1.0"

let manifest_path k4k_dir =
  Filename.concat k4k_dir "manifest.json"

let raise_corrupt msg = raise (Error.K4k_error (Error.E_state_corrupt msg))

(* Inspect any existing manifest for a stale-version mismatch (T17). *)
let validate_manifest_version fields =
  match List.assoc_opt "k4k_version" fields with
  | Some (`String v) when v = k4k_version_string -> ()
  | Some (`String v) ->
      raise_corrupt (Printf.sprintf
        "manifest.json: k4k_version=%s (this build: %s)" v k4k_version_string)
  | _ -> raise_corrupt "manifest.json: missing k4k_version"

let check_existing_manifest path =
  if not (Sys.file_exists path) then ()
  else begin
    let raw = try Persist.read_file path with Error.K4k_error _ -> "" in
    let parsed =
      try Yojson.Safe.from_string raw
      with _ -> raise_corrupt "manifest.json: unparseable JSON"
    in
    match parsed with
    | `Assoc fields -> validate_manifest_version fields
    | _ -> raise_corrupt "manifest.json: not a JSON object"
  end

let json_named name version : Yojson.Safe.t =
  `Assoc [ "name", `String name; "version", `String version ]

let json_interaction_file ~file_path ~file_sha256 ~user_section_hashes : Yojson.Safe.t =
  let hashes : Yojson.Safe.t =
    `Assoc (List.map (fun (k, v) -> (k, `String v)) user_section_hashes)
  in
  `Assoc [
    "path",   `String file_path;
    "sha256", `String file_sha256;
    "last_user_section_hashes", hashes;
  ]

let manifest_json ~file_path ~file_sha256 ~user_section_hashes
    ~agent_name ~agent_version ~verifier_name ~verifier_version : Yojson.Safe.t =
  `Assoc [
    "k4k_version",     `String k4k_version_string;
    "agent_backend",   json_named agent_name agent_version;
    "verifier",        json_named verifier_name verifier_version;
    "interaction_file",
      json_interaction_file ~file_path ~file_sha256 ~user_section_hashes;
    "last_run",        `String (Unix.gettimeofday () |> string_of_float);
  ]

let user_section_hashes (file : Parser.interaction_file) =
  List.filter_map (fun (s : Parser.section) ->
    match s.owner with
    | `User -> Some (s.id, Persist.sha256_hex s.content)
    | `K4k  -> None
  ) file.sections

module Make (B : Agent_backend.S) (V : Verifier.S) : S = struct
  let _ = (B.name, V.name)        (* P15 — refer to the modules to ensure DI. *)

  let read_file_or_raise path =
    if not (Sys.file_exists path) then
      raise (Error.K4k_error (Error.E_file_not_found path));
    Persist.read_file path

  let write_manifest ~k4k_dir ~file_path ~file_content ~parsed =
    let path = manifest_path k4k_dir in
    let user_hashes = user_section_hashes parsed in
    let json = manifest_json
      ~file_path
      ~file_sha256:(Persist.sha256_hex file_content)
      ~user_section_hashes:user_hashes
      ~agent_name:B.name
      ~agent_version:"0.1.0-stub"
      ~verifier_name:V.name
      ~verifier_version:"0.1.0-stub"
    in
    let bytes = Yojson.Safe.pretty_to_string ~std:true json in
    Persist.atomic_write ~path bytes

  let check inputs =
    Persist.ensure_dir inputs.k4k_dir;
    check_existing_manifest (manifest_path inputs.k4k_dir);
    let content = read_file_or_raise inputs.file_path in
    Logger.info inputs.logger "stability.start"
      (`Assoc [ "file", `String inputs.file_path ]);
    let parsed = Parser.parse content in
    let verdict = Stability.check_structural parsed in
    match verdict with
    | Stability.Stable ->
        write_manifest ~k4k_dir:inputs.k4k_dir
          ~file_path:inputs.file_path ~file_content:content ~parsed;
        Logger.info inputs.logger "stability.pass" (`Assoc []);
        Stable_structural
    | Stability.Unstable issues ->
        Logger.info inputs.logger "stability.fail"
          (`Assoc [
             "issue_count", `Int (List.length issues);
           ]);
        raise (Error.K4k_error (Error.E_unstable issues))
end
