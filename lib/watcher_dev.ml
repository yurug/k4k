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
    budget = Budget.default_per_call;
    tier = `A;
    file_path = Some file_path;
  } in
  Version_loop.run ~cfg:v_cfg ~baseline_sha:baseline ~d ?cotype:(Some ct) ()

let read_via_cotype ct ~file_path =
  try Some (Cotype.read_base ct ~file:file_path)
  with Error.K4k_error _ -> None

(* User typed [request: rollback] in the in-file status block.
   Tear down the in-flight version branch (if any) and splice a
   rolled-back status block via the caller's [render_and_save_status]
   continuation. Lives here (next to [try_run_version]) because the
   branch-lifecycle work is paired. *)
let on_user_rollback_directive ~ct:_ ~file_path ~k4k_dir ~emit
    ~render_and_save_status =
  let cwd = Filename.dirname file_path in
  let default_branch = Git.default_branch ~cwd in
  let next_n = Version_persist.next_version_number
                 ~k4k_dir - 1 in
  let n = max 1 next_n in
  let branch = Version.branch_name_of n in
  if Git.branch_exists ~cwd ~name:branch then begin
    let _ = Git.checkout ~cwd ~name:default_branch in
    let _ = Git.delete_branch ~cwd ~name:branch in
    emit "version.rolled_back"
      (`Assoc [ "version", `Int n;
                "branch", `String branch ])
  end;
  let s : Inline_blocks.status =
    { version_n = n; state = "rolled-back";
      tier_dist = { tier_a = 0; tier_b = 0; tier_c = 0 };
      pending_user_edits = 0;
      last_activity = Inline_blocks.timestamp_now ();
      open_tradeoffs = 0; } in
  render_and_save_status ~status_block:(Inline_blocks.render_status s)

(* Negative-cache file. When formalize fails, we persist the content
   hash here so the next watcher tick can skip the call until the
   user edits the spec — without this gate, the watcher re-runs
   formalize on every stable snapshot (≤500ms), burning API credits
   for nothing. Cleared on the first successful formalize. *)
let neg_cache_path ~k4k_dir =
  Filename.concat k4k_dir "last_failed_formalize_hash"

let read_neg_cache ~k4k_dir =
  let p = neg_cache_path ~k4k_dir in
  if not (Sys.file_exists p) then None
  else try Some (String.trim (Persist.read_file p)) with _ -> None

let write_neg_cache ~k4k_dir ~hash =
  let p = neg_cache_path ~k4k_dir in
  try Persist.ensure_dir k4k_dir;
      Persist.atomic_write ~path:p hash
  with _ -> ()

let clear_neg_cache ~k4k_dir =
  let p = neg_cache_path ~k4k_dir in
  if Sys.file_exists p then try Sys.remove p with _ -> ()

let splice_formalize_clarification ~ct ~file_path ~emit
    (fail : Watcher_form.failure) =
  let issues = fail.issues in
  let questions =
    List.map (fun (i : Error.issue) ->
      Printf.sprintf "[formalize] %s: %s" i.section i.details) issues
  in
  try
    Cotype.append_clarification ct ~path:file_path ~questions;
    emit "clarification.appended"
      (`Assoc [ "count", `Int (List.length issues);
                "source", `String "formalize" ])
  with Error.K4k_error e ->
    emit "clarification.write_failed"
      (`Assoc [ "code", `String (Error.code_id e);
                "render", `String (Error.render e) ])

(* Real formalization: derive D from the user's prose using the same
   agent backend used for gap-steps. Returns [Ok d] on success;
   [Error fail] (carrying issues) when D cannot be derived. On
   failure we splice a [## k4k:clarification:] block listing the
   issues AND record the content hash so the next tick skips the
   call until the user actually edits the spec. *)
let formalize ~k4k_dir ~ct ~file_path ~emit ~agent_invoke
    : (Characterization.t, string) result =
  match read_via_cotype ct ~file_path with
  | None -> Error "could not read interaction file via cotype"
  | Some content ->
      let h = Persist.sha256_hex content in
      (match read_neg_cache ~k4k_dir with
       | Some prev when prev = h ->
           emit "formalize.skip"
             (`Assoc [ "reason",
                       `String "no spec change since last failure";
                       "hash", `String h ]);
           Error "no spec change since last failure"
       | _ ->
           (match Watcher_form.run ~k4k_dir ~content ~agent_invoke ~emit with
            | Ok d -> clear_neg_cache ~k4k_dir; Ok d
            | Error fail ->
                splice_formalize_clarification ~ct ~file_path ~emit fail;
                write_neg_cache ~k4k_dir ~hash:h;
                Error fail.reason))

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

let dispatch_with_typed_errors ~file_path ~k4k_dir ~emit ~ct ~d
    ~agent_invoke =
  try
    (match dispatch_one ~file_path ~k4k_dir ~emit ~ct ~d ~agent_invoke with
     | Version_loop.Done _ -> `Done
     | Version_loop.Rolled_back { outcomes } ->
         Rollback_feedback.post_rollback_clarification
           ~ct ~file_path ~emit ~outcomes;
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

