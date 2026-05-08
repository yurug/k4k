(** [Watcher_dev] — development-half helpers, factored out of
    [Watcher_loop] to keep both files under the 200-line cap.

    Loads a [Characterization.t] from a test-only env knob
    (production v2-batch-4a: real formalization is wired in batch 4b),
    composes a real [Version_loop.config] (with agent + verifier
    closures, ADR-013 §2 step 3 direct-commit workflow), then drives
    [Version_loop]. *)

type emit_fn = string -> Yojson.Safe.t -> unit

let load_d_from_env () : Characterization.t option =
  match Sys.getenv_opt "K4K_TEST_D_PATH" with
  | None | Some "" -> None
  | Some path ->
      if not (Sys.file_exists path) then None
      else
        try
          let raw = Persist.read_file path in
          let j = Yojson.Safe.from_string raw in
          let d = Characterization_decoder.of_yojson j in
          Some (Canonicalize.canonicalize d)
        with _ -> None

let canned_invoke ~emit : Version_loop.agent_invoke =
  match Sys.getenv_opt "K4K_STUB_RESPONSES" with
  | None | Some "" ->
      fun ~purpose:_ ~prompt:_ ~budget:_ ->
        emit "agent.no_canned" (`Assoc []);
        `Tool_error "no K4K_STUB_RESPONSES configured"
  | Some path ->
      (match Backend_canned.load_from_path path with
       | Error msg ->
           emit "agent.canned_load_error"
             (`Assoc [ "error", `String msg ]);
           fun ~purpose:_ ~prompt:_ ~budget:_ ->
             `Tool_error ("canned load: " ^ msg)
       | Ok t ->
           Backend_canned.invoke t)

let verifier_invoke ~k4k_dir ~d : Version_loop.verifier_run =
  let cfg = { Verifier_external.default_config with
              command = d.Characterization.verifier_command;
              k4k_dir = Some k4k_dir; } in
  let v = Verifier_external.create cfg in
  fun ~workdir ~focus -> Verifier_external.run v ~workdir ~focus

(* The watcher's status-block writes (process_stable + on_rollback in
   Watcher_loop) mutate <file.k4k> in place via cotype. Before cutting
   a version branch we commit any such pending change as a [k4k]-
   authored snapshot on the default branch so [Gap_step.preflight]'s
   clean-tree check passes inside the version. *)
let commit_pending_status ~cwd ~emit =
  let clean, _ = Git.is_clean ~cwd in
  if not clean then
    match Git.commit_all ~cwd ~message:"[k4k] snapshot pre-version" with
    | Ok () -> emit "version.pre_snapshot" (`Assoc [])
    | Error e -> emit "version.pre_snapshot_error"
                   (`Assoc [ "error", `String e ])

let dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d =
  let cwd = Filename.dirname file_path in
  commit_pending_status ~cwd ~emit;
  let baseline = match Git.head_sha ~cwd with
    | Ok s -> s | Error _ -> ""
  in
  let default_branch = Git.default_branch ~cwd in
  let v_cfg : Version_loop.config = {
    cwd;
    k4k_dir;
    default_branch;
    emit;
    delete_branch_on_done = true;
    agent_invoke = canned_invoke ~emit;
    verifier_run = verifier_invoke ~k4k_dir ~d;
    budget = 1000;
    tier = `A;
  } in
  Version_loop.run ~cfg:v_cfg ~baseline_sha:baseline ~d ?cotype:(Some ct) ()

(** Try to drive the development half of the watcher loop. Returns
    [`Done] iff a version completed; [`Pending] otherwise (rollback,
    or no [K4K_TEST_D_PATH]). *)
let try_run_version ~file_path ~k4k_dir ~emit ct : [ `Done | `Pending ] =
  match load_d_from_env () with
  | None ->
      emit "version.skip"
        (`Assoc [ "reason",
                  `String "no K4K_TEST_D_PATH; awaiting batch-4b formalization" ]);
      `Pending
  | Some d ->
      try
        (match dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d with
         | Done _ -> `Done
         | Rolled_back -> `Pending)
      with
      | Error.K4k_error e ->
          emit "version.error" (`Assoc [
            "code", `String (Error.code_id e);
            "render", `String (Error.render e);
          ]);
          `Pending
      | exn ->
          emit "version.exn" (`Assoc [
            "exn", `String (Printexc.to_string exn);
          ]);
          `Pending

let render_done_status ~version_n ~tier_dist =
  let s : Inline_blocks.status = {
    version_n; state = "done";
    tier_dist;
    pending_user_edits = 0;
    last_activity = Inline_blocks.timestamp_now ();
    open_tradeoffs = 0;
  } in
  Inline_blocks.render_status s

let save_status_block ~file_path ct ~bytes =
  try
    let opened = Cotype.open_ ct ~file:file_path in
    match opened with
    | Error _ -> ()
    | Ok r ->
        let base = Persist.read_file r.base_path in
        let merged = Status_splice.replace_or_append base bytes in
        let _ = Cotype.save ct ~file:file_path
                  ~base_sha:r.base_sha ~actor:"agent:k4k"
                  ~bytes:merged in ()
  with _ -> ()

let after_version_done ~file_path ct ~version_n ~tier_dist =
  let block = render_done_status ~version_n ~tier_dist in
  save_status_block ~file_path ct ~bytes:block

let pending_user_edits ~baseline_hashes ~current_hashes : int =
  List.length (List.filter (fun (k, v) ->
    match List.assoc_opt k current_hashes with
    | None -> true
    | Some v' -> v <> v') baseline_hashes)
