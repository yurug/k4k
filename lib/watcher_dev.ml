(** [Watcher_dev] — development-half helpers, factored out of
    [Watcher_loop] to keep both files under the 200-line cap.

    v2 batch 4b: real formalization replaces the [K4K_TEST_D_PATH] knob.
    On a stable spec, [try_run_version] runs the two-run formalization
    protocol via the same [Backend_canned] (test) / [Backend_external]
    (production) backend used for gap-step calls, then drives
    [Version_loop]. *)

type emit_fn = string -> Yojson.Safe.t -> unit

(** Lazily-resolved agent-invoke closure: shared across formalization
    and gap-step. Per-purpose queues in [Backend_canned] mean a single
    handle suffices. Production swaps in [Backend_external]. *)
let resolve_invoke ~emit : Version_loop.agent_invoke =
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

let commit_user_pending ~cwd ~emit =
  let clean, _ = Git.is_clean ~cwd in
  if not clean then begin
    match Git.commit_all ~cwd ~message:"[k4k] file: pruning + housekeeping" with
    | Ok () -> emit "watcher.commit_pending" (`Assoc [])
    | Error e ->
        emit "watcher.commit_pending_error"
          (`Assoc [ "error", `String e ])
  end

let dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d ~agent_invoke =
  let cwd = Filename.dirname file_path in
  commit_user_pending ~cwd ~emit;
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
    agent_invoke;
    verifier_run = verifier_invoke ~k4k_dir ~d;
    budget = 1000;
    tier = `A;
    file_path = Some file_path;
  } in
  Version_loop.run ~cfg:v_cfg ~baseline_sha:baseline ~d ?cotype:(Some ct) ()

let read_via_cotype ct ~file_path =
  try Some (Cotype.read_base ct ~file:file_path)
  with Error.K4k_error _ -> None

(* Real formalization: derive D from the user's prose using the same
   agent backend used for gap-steps. Returns [Ok d] on success;
   [Error reason] when D cannot be derived (the watcher will skip the
   version this tick and retry on the next stability snapshot). *)
let formalize ~k4k_dir ~ct ~file_path ~emit ~agent_invoke
    : (Characterization.t, string) result =
  match read_via_cotype ct ~file_path with
  | None -> Error "could not read interaction file via cotype"
  | Some content ->
      Watcher_form.run ~k4k_dir ~content ~agent_invoke ~emit

(** Try to drive the development half of the watcher loop. Returns
    [`Done] iff a version completed; [`Pending] otherwise (rollback,
    formalization failure, or version-start error). *)
let try_run_version ~file_path ~k4k_dir ~emit ct : [ `Done | `Pending ] =
  let agent_invoke = resolve_invoke ~emit in
  match formalize ~k4k_dir ~ct ~file_path ~emit ~agent_invoke with
  | Error reason ->
      emit "version.skip"
        (`Assoc [ "reason", `String ("formalize: " ^ reason) ]);
      `Pending
  | Ok d ->
      try
        (match dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d
                 ~agent_invoke with
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
