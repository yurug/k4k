(** [Gap_branch] — git scratch-branch lifecycle for [Gap_step] per
    Q3.2. Pre-flight (clean tree + repo check) included. *)

let raise_state msg =
  raise (Error.K4k_error (Error.E_state_corrupt msg))

let preflight ~workdir =
  if not (Git.is_repo ~cwd:workdir) then
    raise_state
      "gap-step: workdir is not a git repository (run 'git init')";
  let clean, dirty = Git.is_clean ~cwd:workdir in
  if not clean then
    raise_state
      (Printf.sprintf
         "gap-step: working tree is dirty (%d paths); commit or stash"
         (List.length dirty))

let create ~workdir ~property_id =
  let name = Git.scratch_branch_name ~property_id in
  if Git.branch_exists ~cwd:workdir ~name then
    raise_state
      (Printf.sprintf "scratch branch already exists: %s; \
                       see 'git branch --list k4k/gap/*'" name);
  match Git.create_branch ~cwd:workdir ~name with
  | Ok () -> name
  | Error msg ->
      raise_state
        (Printf.sprintf "git checkout -b %s failed: %s" name msg)

let discard ~workdir ~base ~name =
  let _ = Git.checkout ~cwd:workdir ~name:base in
  let _ = Git.delete_branch ~cwd:workdir ~name in
  ()

let merge ~workdir ~base ~name : (unit, string) result =
  match Git.checkout ~cwd:workdir ~name:base with
  | Error e -> Error e
  | Ok () ->
      (match Git.merge_ff_only ~cwd:workdir ~name with
       | Error e -> Error e
       | Ok () ->
           let _ = Git.delete_branch ~cwd:workdir ~name in
           Ok ())
