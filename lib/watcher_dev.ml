(** [Watcher_dev] — development-half helpers, factored out of
    [Watcher_loop] to keep both files under the 200-line cap.

    Loads a [Characterization.t] from a test-only env knob
    (production v2-batch-3: real formalization is wired in batch 4),
    then drives [Version_loop]. The [emit] argument decouples this
    module from [Watcher_loop]'s config record. *)

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

let dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d =
  let cwd = Filename.dirname file_path in
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
                  `String "no K4K_TEST_D_PATH; awaiting batch-4 formalization" ]);
      `Pending
  | Some d ->
      (match dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d with
       | Done _ -> `Done
       | Rolled_back -> `Pending)

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
