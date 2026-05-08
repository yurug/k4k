(** [Gap_step] — direct-commit gap-step workflow per ADR-013 §2 step 3
    (v2 retrofit).

    A step:
      1. validates the working tree is a git repo and clean;
      2. composes a tier-aware prompt (Gap_prompt);
      3. asks the agent for a unified diff;
      4. applies the diff DIRECTLY to the working tree;
      5. runs the verifier in [focus] mode;
      6. accepts (commit_accept on the version branch) iff verifier
         reports [`Established] for the focus and no regression of
         previously-established properties;
      7. otherwise [git reset --hard HEAD] (rewinds to the last
         accepted commit) and increments [failure_count]. After 3
         strikes the outcome is [Tradeoff] (placeholder for the
         batch-4b proposal-pause-resume flow). *)

type 'b deps = {
  k4k_dir : string;
  workdir : string;
  agent_invoke :
    purpose:Agent_backend.purpose ->
    prompt:string -> budget:int -> Agent_backend.result;
  verifier_run :
    workdir:string -> focus:string list -> Verifier.run_result;
  logger : Logger.t;
  budget_remaining : int ref;
  agent_backend : 'b;
  tier : [ `A | `B | `C ];
}

type outcome =
  | Accepted of { property : Property.t; commit_sha : string }
  | Rejected of { property : Property.t; reason : string }
  | Blocked of Property.t
  | Tradeoff of { property : Property.t }
  | Budget_exhausted

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

let regressed ~prev_status ~result =
  let by_p = result.Verifier.by_property in
  List.exists (fun (pid, st) ->
    match List.assoc_opt pid prev_status, st with
    | Some `Established, `Contradicted -> true
    | _ -> false) by_p

let persist_agent_run ~k4k_dir ~property_id ~prompt ~response ~outcome =
  let id = Persist.agent_run_id () in
  let verdict = Canonical_json.to_string (`Assoc [
    "id", `String id;
    "purpose", `String "gap-step";
    "property_id", `String property_id;
    "outcome", `String outcome;
  ]) in
  Persist.write_agent_run ~k4k_dir ~run_id:id
    ~prompt ~response ~verdict;
  id

let log_outcome (lg : Logger.t) ev p extra =
  Logger.info lg ev (`Assoc ([
    "property_id", `String p.Property.id;
    "failure_count", `Int p.failure_count;
  ] @ extra))

let bump_and_classify ~deps p reason =
  let p2 = Property.bump_failure p in
  if p2.Property.failure_count >= 3 then begin
    log_outcome deps.logger "gap-step.tradeoff" p2
      [ "reason", `String reason ];
    Tradeoff { property = p2 }
  end else begin
    log_outcome deps.logger "gap-step.reject" p2
      [ "reason", `String reason ];
    Rejected { property = p2; reason }
  end

let rewind_or_state cwd =
  match Git.reset_hard ~cwd ~ref:"HEAD" with
  | Ok () -> ()
  | Error msg ->
      raise_state ("gap-step: git reset --hard failed: " ^ msg)

let on_no_diff ~deps ~p ~prompt ~response =
  let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
    ~property_id:p.Property.id ~prompt ~response
    ~outcome:"rejected" in
  bump_and_classify ~deps p "no diff in response"

let on_apply_fail ~deps ~p ~prompt ~response e =
  rewind_or_state deps.workdir;
  let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
    ~property_id:p.Property.id ~prompt ~response
    ~outcome:"rejected" in
  bump_and_classify ~deps p ("diff did not apply: " ^ e)

let on_verifier_error ~deps ~p ~prompt ~response msg =
  rewind_or_state deps.workdir;
  let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
    ~property_id:p.Property.id ~prompt ~response
    ~outcome:"rejected" in
  bump_and_classify ~deps p ("verifier tool error: " ^ msg)

let commit_accepted ~deps ~p ~prompt ~response =
  let msg = Printf.sprintf "[k4k] establish %s" p.Property.id in
  match Version.commit_accept ~cwd:deps.workdir
          ~property_id:p.Property.id ~message:msg with
  | Error e -> on_apply_fail ~deps ~p ~prompt ~response
                 ("commit failed: " ^ e)
  | Ok sha ->
      let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
        ~property_id:p.id ~prompt ~response ~outcome:"applied" in
      let p2 = Property.regen_risk
                 (Property.with_status p `Established) in
      log_outcome deps.logger "gap-step.accept" p2
        [ "commit_sha", `String sha ];
      Accepted { property = p2; commit_sha = sha }

let on_verifier_ok ~deps ~p ~prev_status ~prompt ~response
    (r : Verifier.result_ok) =
  let st = List.assoc_opt p.Property.id r.by_property in
  let regr = regressed ~prev_status ~result:r in
  if st = Some `Established && not regr then
    commit_accepted ~deps ~p ~prompt ~response
  else begin
    rewind_or_state deps.workdir;
    let reason =
      if regr then "patch regressed an established property"
      else "verifier did not establish the focus property" in
    let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
      ~property_id:p.id ~prompt ~response ~outcome:"rejected" in
    bump_and_classify ~deps p reason
  end

let try_apply_and_verify ~deps ~p ~prev_status ~prompt ~response_text =
  match Diff_extract.extract_diff response_text with
  | None -> on_no_diff ~deps ~p ~prompt ~response:response_text
  | Some diff ->
      Sigint.raise_if_needed ();
      (match Git.apply_diff ~cwd:deps.workdir ~diff with
       | Error e ->
           on_apply_fail ~deps ~p ~prompt ~response:response_text e
       | Ok () ->
           Sigint.raise_if_needed ();
           match deps.verifier_run ~workdir:deps.workdir
                   ~focus:[p.Property.id] with
           | `Tool_error msg ->
               on_verifier_error ~deps ~p ~prompt
                 ~response:response_text msg
           | `Ok r ->
               on_verifier_ok ~deps ~p ~prev_status ~prompt
                 ~response:response_text r)

let dispatch_response ~deps ~p ~prev_status ~prompt = function
  | `Budget_exhausted -> Budget_exhausted
  | `Tool_error msg ->
      let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
        ~property_id:p.Property.id ~prompt ~response:""
        ~outcome:"tool-error" in
      bump_and_classify ~deps p ("agent: " ^ msg)
  | `Ok (r : Agent_backend.response) ->
      deps.budget_remaining :=
        max 0 (!(deps.budget_remaining) - r.budget_used);
      try_apply_and_verify ~deps ~p ~prev_status ~prompt
        ~response_text:r.text

let step ~deps ~d ~current_summary ~prev_status ~property:p : outcome =
  Sigint.raise_if_needed ();
  preflight ~workdir:deps.workdir;
  (* P6 — three-strikes guard. A property arriving here with
     failure_count >= 3 has already been the subject of a
     [Tradeoff] outcome upstream; the watcher's [reset_for_tier]
     resets failure_count to 0 before any retry, so reaching this
     branch indicates the version_loop is replaying a property
     without the reset (a bug). [Blocked] preserves the safety
     post-condition: never call the agent on a known-stuck
     property. *)
  if p.Property.failure_count >= 3 then begin
    log_outcome deps.logger "gap-step.blocked" p [];
    Blocked p
  end else
    let prompt = Gap_prompt.compose ~tier:deps.tier p d ~current_summary in
    let budget_now = !(deps.budget_remaining) in
    if budget_now <= 0 then Budget_exhausted
    else begin
      Logger.info deps.logger "gap-step.start"
        (`Assoc [ "property_id", `String p.id;
                  "risk_score", `Float p.risk_score ]);
      dispatch_response ~deps ~p ~prev_status ~prompt
        (deps.agent_invoke ~purpose:`Gap_step ~prompt
           ~budget:budget_now)
    end
