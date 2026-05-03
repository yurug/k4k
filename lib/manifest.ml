(** [Manifest] — read/write/inspect [.k4k/manifest.json] per
    [kb/spec/data-model.md#manifest]. *)

let k4k_version_string = "0.1.0"

let path k4k_dir = Filename.concat k4k_dir "manifest.json"

type t = (string * Yojson.Safe.t) list option

let raise_corrupt msg =
  raise (Error.K4k_error (Error.E_state_corrupt msg))

let validate_version fs =
  match List.assoc_opt "k4k_version" fs with
  | Some (`String v) when v = k4k_version_string -> ()
  | Some (`String v) ->
      raise_corrupt (Printf.sprintf
        "manifest.json: k4k_version=%s (this build: %s)" v k4k_version_string)
  | _ -> raise_corrupt "manifest.json: missing k4k_version"

let read_or_init ~k4k_dir : t =
  let p = path k4k_dir in
  if not (Sys.file_exists p) then None
  else
    let raw = try Persist.read_file p with Error.K4k_error _ -> "" in
    let parsed =
      try Yojson.Safe.from_string raw
      with _ -> raise_corrupt "manifest.json: unparseable JSON"
    in
    match parsed with
    | `Assoc fields -> validate_version fields; Some fields
    | _ -> raise_corrupt "manifest.json: not a JSON object"

let user_section_hashes (m : t) : (string * string) list =
  match m with
  | None -> []
  | Some fs ->
      (match List.assoc_opt "interaction_file" fs with
       | Some (`Assoc ifs) ->
           (match List.assoc_opt "last_user_section_hashes" ifs with
            | Some (`Assoc kvs) ->
                List.map (fun (k, v) ->
                  match v with `String s -> (k, s) | _ -> (k, "")) kvs
            | _ -> [])
       | _ -> [])

let desired_hash (m : t) : string option =
  match m with
  | None -> None
  | Some fs ->
      (match List.assoc_opt "desired" fs with
       | Some (`Assoc dfs) ->
           (match List.assoc_opt "hash" dfs with
            | Some (`String s) when s <> "" -> Some s
            | _ -> None)
       | _ -> None)

(* Build a record JSON with optional command. Used for both verifier
   and agent_backend fields so audits can reconstruct the exact
   invocation. Schema is additive: existing manifests without
   [command] still validate. *)
let json_with_command ~name ~version ~command : Yojson.Safe.t =
  let fields = [
    "name", `String name;
    "version", `String version;
  ] in
  let fields = match command with
    | None -> fields
    | Some xs ->
        fields @ [ "command", `List (List.map (fun s -> `String s) xs) ]
  in
  `Assoc fields

let interaction_file_json ~file_path ~file_sha256 ~user_section_hashes
    : Yojson.Safe.t =
  let hashes : Yojson.Safe.t =
    `Assoc (List.map (fun (k, v) -> (k, `String v)) user_section_hashes)
  in
  `Assoc [
    "path", `String file_path;
    "sha256", `String file_sha256;
    "last_user_section_hashes", hashes;
  ]

let build ?verifier_command ?backend_command
    ~file_path ~file_sha256 ~user_section_hashes
    ~agent_name ~agent_version ~verifier_name ~verifier_version
    ~desired_hash () : Yojson.Safe.t =
  `Assoc [
    "k4k_version", `String k4k_version_string;
    "agent_backend", json_with_command
                       ~name:agent_name ~version:agent_version
                       ~command:backend_command;
    "verifier", json_with_command ~name:verifier_name
                  ~version:verifier_version
                  ~command:verifier_command;
    "interaction_file",
      interaction_file_json ~file_path ~file_sha256 ~user_section_hashes;
    "desired", `Assoc [
      "path", `String "characterization/desired/spec.json";
      "hash", `String desired_hash;
    ];
    "last_run", `String (Unix.gettimeofday () |> string_of_float);
  ]
