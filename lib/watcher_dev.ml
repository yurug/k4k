(** [Watcher_dev] — development-half helpers, factored out of
    [Watcher_loop] to keep both files under the 200-line cap.

    v2 batch 4b: real formalization replaces the [K4K_TEST_D_PATH] knob.
    On a stable spec, [try_run_version] runs the two-run formalization
    protocol via the same [Backend_canned] (test) / [Backend_external]
    (production) backend used for gap-step calls, then drives
    [Version_loop]. *)

type emit_fn = string -> Yojson.Safe.t -> unit

(** Resolve the agent-invoke closure ONCE at watcher startup;
    delegated to [Backend_resolve.resolve] (audit-2026-05-08-axis6
    H-3). The resulting closure is reused across every
    [try_run_version] iteration. [k4k_dir] is threaded through so
    [Config.read_or_create] can bootstrap [.k4k/config.json] on
    first run. *)
let resolve_invoke ~emit ~k4k_dir : Version_loop.agent_invoke =
  Backend_resolve.resolve ~emit ~k4k_dir

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

(** Try to drive the development half of the watcher loop. The
    [agent_invoke] closure must be allocated ONCE per watcher run and
    threaded through every iteration (see [resolve_invoke]). The
    three outcomes are:
    - [`Done] — version-loop returned [Done] (all properties
      established, merged + tagged on the default branch);
    - [`Rolled_back] — version-loop returned [Rolled_back] (or
      raised); a version branch may still exist as scratch state for
      audit;
    - [`Skipped] — no version was attempted (formalization failed, or
      [Version_persist.last_completed_d_hash] matched the new
      D-hash so the idempotence gate fired).

    Both [`Done] and [`Rolled_back] are terminal version outcomes —
    [Watcher_loop.on_stable] treats them equally for the
    [exit_on_done] / [max_versions] gates. [`Skipped] is non-terminal:
    the loop sleeps and tries again. *)
(* Ralph-loop step 2 (v2 batch 27): when a version rolls back,
   splice a clarification block summarizing the deferred properties
   + their last failure reasons. The watcher's next stable tick
   re-formalizes — but the user has been told what just happened
   and can edit the user-owned sections to refine the spec, or
   trigger a tradeoff degradation when re-proposed. *)
let post_rollback_clarification ~ct ~file_path ~emit ~outcomes =
  let deferred =
    List.filter (fun (po : Version_finalize.prop_outcome) ->
      po.status <> "established") outcomes in
  if deferred = [] then ()
  else
    let questions =
      ("k4k completed a version that was rolled back. Edit the \
        user-owned sections below to refine the spec, or accept a \
        degraded tier when proposed.")
      :: List.map (fun (po : Version_finalize.prop_outcome) ->
           let r = match po.failure_reason with
             | Some s -> s
             | None -> "(no recorded reason)" in
           Printf.sprintf
             "Property %s deferred: %s" po.id r) deferred
    in
    try
      Cotype.append_clarification ct ~path:file_path ~questions;
      emit "clarification.rolled_back_summary"
        (`Assoc [ "deferred", `Int (List.length deferred);
                  "property_ids",
                  `List (List.map (fun (po : Version_finalize.prop_outcome) ->
                          `String po.id) deferred) ])
    with Error.K4k_error e ->
      emit "clarification.write_failed"
        (`Assoc [ "code", `String (Error.code_id e);
                  "render", `String (Error.render e); ])

let dispatch_with_typed_errors ~file_path ~k4k_dir ~emit ~ct ~d
    ~agent_invoke =
  try
    (match dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d ~agent_invoke with
     | Version_loop.Done _ -> `Done
     | Version_loop.Rolled_back { outcomes } ->
         post_rollback_clarification ~ct ~file_path ~emit ~outcomes;
         `Rolled_back)
  with
  | Error.K4k_error e ->
      emit "version.error" (`Assoc [
        "code", `String (Error.code_id e);
        "render", `String (Error.render e); ]);
      `Rolled_back
  | exn ->
      emit "version.exn"
        (`Assoc [ "exn", `String (Printexc.to_string exn) ]);
      `Rolled_back

let start_or_skip ~file_path ~k4k_dir ~emit ~ct ~d ~agent_invoke =
  (* Idempotence gate (audit-2026-05-08-axis6 H-3 partner): if the
     previously-completed version already converged at this exact
     D-hash, do not start a new version. Without this gate the
     watcher main loop spins on stable specs. *)
  match Version_persist.last_completed_d_hash ~k4k_dir with
  | Some prev when prev = d.Characterization.hash ->
      emit "version.skip"
        (`Assoc [ "reason", `String "no-spec-change";
                  "d_hash", `String d.hash ]);
      `Skipped
  | _ -> dispatch_with_typed_errors
           ~file_path ~k4k_dir ~emit ~ct ~d ~agent_invoke

let try_run_version ~file_path ~k4k_dir ~emit ~agent_invoke ct
    : [ `Done | `Rolled_back | `Skipped ] =
  match formalize ~k4k_dir ~ct ~file_path ~emit ~agent_invoke with
  | Error reason ->
      emit "version.skip"
        (`Assoc [ "reason", `String ("formalize: " ^ reason) ]);
      `Skipped
  | Ok d -> start_or_skip ~file_path ~k4k_dir ~emit ~ct ~d ~agent_invoke

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

