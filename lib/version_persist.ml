(** [Version_persist] — filesystem I/O for [.k4k/version/<n>/].
    Pure-disk; no git. *)

let dir_for ~k4k_dir ~number =
  Filename.concat k4k_dir
    (Filename.concat "version" (string_of_int number))

let manifest_path ~k4k_dir ~number =
  Filename.concat (dir_for ~k4k_dir ~number) "manifest.json"

let d_spec_path ~k4k_dir ~number =
  Filename.concat (dir_for ~k4k_dir ~number) "D-spec.json"

let tiers_path ~k4k_dir ~number =
  Filename.concat (dir_for ~k4k_dir ~number) "tiers.json"

let audit_path ~k4k_dir ~number =
  Filename.concat (dir_for ~k4k_dir ~number) "audit.md"

let agent_runs_dir ~k4k_dir ~number =
  Filename.concat (dir_for ~k4k_dir ~number) "agent-runs"

let clarifications_dir ~k4k_dir ~number =
  Filename.concat (dir_for ~k4k_dir ~number) "clarifications"

let tradeoffs_dir ~k4k_dir ~number =
  Filename.concat (dir_for ~k4k_dir ~number) "tradeoffs"

let ensure_dirs ~k4k_dir ~number =
  Persist.ensure_dir (dir_for ~k4k_dir ~number);
  Persist.ensure_dir (agent_runs_dir ~k4k_dir ~number);
  Persist.ensure_dir (clarifications_dir ~k4k_dir ~number);
  Persist.ensure_dir (tradeoffs_dir ~k4k_dir ~number)

(** Write the per-version manifest including tool versions, baseline
    SHA, branch name and (optionally) the completed tag. *)
let write_manifest ~k4k_dir ~v ?tag_name
    ?(cotype_version = "")
    ?(agent_name = "") ?(agent_version = "")
    ?(verifier_name = "") ?(verifier_version = "")
    () =
  let tag_field = match tag_name with
    | None -> [] | Some t -> ["tag", `String t]
  in
  let j : Yojson.Safe.t = `Assoc (
    [ "k4k_version",   `String "0.1.0";
      "version", Version.to_yojson v;
      "tools", `Assoc [
        "cotype",   `String cotype_version;
        "agent",    `Assoc [ "name", `String agent_name;
                             "version", `String agent_version ];
        "verifier", `Assoc [ "name", `String verifier_name;
                             "version", `String verifier_version ];
      ];
    ] @ tag_field)
  in
  ensure_dirs ~k4k_dir ~number:v.Version.number;
  Persist.atomic_write
    ~path:(manifest_path ~k4k_dir ~number:v.number)
    (Yojson.Safe.pretty_to_string ~std:true j)

let write_d_spec ~k4k_dir ~number ~d =
  ensure_dirs ~k4k_dir ~number;
  let bytes = Canonical_json.to_string
                (Characterization_json.to_yojson d) in
  Persist.atomic_write ~path:(d_spec_path ~k4k_dir ~number) bytes

let write_tiers ~k4k_dir ~number ~tiers =
  ensure_dirs ~k4k_dir ~number;
  let j : Yojson.Safe.t = `Assoc (
    List.map (fun (pid, tier) ->
      let s = match tier with
        | `A -> "A" | `B -> "B" | `C -> "C" in
      (pid, `String s)) tiers)
  in
  Persist.atomic_write ~path:(tiers_path ~k4k_dir ~number)
    (Yojson.Safe.pretty_to_string ~std:true j)

let write_audit ~k4k_dir ~number ~content =
  ensure_dirs ~k4k_dir ~number;
  Persist.atomic_write ~path:(audit_path ~k4k_dir ~number) content

(** Discover the next version number by scanning [.k4k/version/]. *)
let next_version_number ~k4k_dir : int =
  let root = Filename.concat k4k_dir "version" in
  if not (Sys.file_exists root) || not (Sys.is_directory root) then 1
  else
    let entries = try Sys.readdir root with _ -> [||] in
    let nums = Array.fold_left (fun acc e ->
      match int_of_string_opt e with
      | Some n -> n :: acc | None -> acc) [] entries
    in
    match List.sort compare nums with
    | [] -> 1
    | xs -> 1 + List.fold_left max 0 xs
