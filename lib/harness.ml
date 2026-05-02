type check_inputs = {
  file_path : string;
  k4k_dir   : string;
  logger    : Logger.t;
}

type check_outcome =
  | Stable_structural
  | Stable_full
  | Unstable

module type S = sig
  val check : check_inputs -> check_outcome
end

let raise_unstable issues =
  raise (Error.K4k_error (Error.E_unstable issues))

module Make (B : Agent_backend.S) (V : Verifier.S) : S = struct
  let _ = (B.name, V.name)

  let read_file_or_raise path =
    if not (Sys.file_exists path) then
      raise (Error.K4k_error (Error.E_file_not_found path));
    Persist.read_file path

  (* Step-1 surface: structural-only [check] used by the
     pre-step-2 contract. *)
  let check inputs =
    Persist.ensure_dir inputs.k4k_dir;
    let _ = Manifest.read_or_init ~k4k_dir:inputs.k4k_dir in
    let content = read_file_or_raise inputs.file_path in
    Logger.info inputs.logger "stability.start"
      (`Assoc [ "file", `String inputs.file_path ]);
    let parsed = Parser.parse content in
    match Stability.check_structural parsed with
    | Stability.Stable ->
        let user_hashes = Stability.user_section_hashes parsed in
        let mj = Manifest.build
          ~file_path:inputs.file_path
          ~file_sha256:(Persist.sha256_hex content)
          ~user_section_hashes:user_hashes
          ~agent_name:B.name ~agent_version:"0.1.0-stub"
          ~verifier_name:V.name ~verifier_version:"0.1.0-stub"
          ~desired_hash:"" in
        Persist.atomic_write
          ~path:(Manifest.path inputs.k4k_dir)
          (Yojson.Safe.pretty_to_string ~std:true mj);
        Logger.info inputs.logger "stability.pass" (`Assoc []);
        Stable_structural
    | Stability.Unstable issues ->
        Logger.info inputs.logger "stability.fail"
          (`Assoc [ "issue_count", `Int (List.length issues) ]);
        raise_unstable issues
end
