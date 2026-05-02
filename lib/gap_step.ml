(** [Gap_step] — one full iteration of the convergence loop per
    [kb/spec/algorithms.md#gap-step].

    A step:
      1. picks the highest-risk non-blocked property;
      2. composes a prompt (Gap_prompt);
      3. asks the agent for a unified-diff;
      4. applies the diff on a fresh scratch git branch (Gap_branch);
      5. runs the verifier in [focus] mode;
      6. accepts (FF-merge) iff the verifier reports `Established` for
         the focus property AND no previously-established property
         regressed (P5);
      7. otherwise rejects (discards branch, increments failure count). *)

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
}

type outcome =
  | Accepted of Property.t
  | Rejected of Property.t * string
  | Blocked of Property.t
  | Budget_exhausted

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

let on_no_diff ~deps ~p ~prompt ~response =
  let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
    ~property_id:p.Property.id ~prompt ~response
    ~outcome:"rejected" in
  let p2 = Property.bump_failure p in
  log_outcome deps.logger "gap-step.reject" p2
    [ "reason", `String "no diff in response" ];
  Rejected (p2, "no diff in response")

let on_apply_fail ~deps ~p ~prompt ~response ~base ~name e =
  Gap_branch.discard ~workdir:deps.workdir ~base ~name;
  let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
    ~property_id:p.Property.id ~prompt ~response
    ~outcome:"rejected" in
  let p2 = Property.bump_failure p in
  log_outcome deps.logger "gap-step.reject" p2
    [ "reason", `String ("diff did not apply: " ^ e) ];
  Rejected (p2, Printf.sprintf "diff did not apply: %s" e)

let on_verifier_error ~deps ~p ~prompt ~response ~base ~name msg =
  Gap_branch.discard ~workdir:deps.workdir ~base ~name;
  let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
    ~property_id:p.Property.id ~prompt ~response
    ~outcome:"rejected" in
  let p2 = Property.bump_failure p in
  log_outcome deps.logger "gap-step.reject" p2
    [ "reason", `String ("verifier error: " ^ msg) ];
  Rejected (p2, "verifier tool error: " ^ msg)

let on_verifier_ok ~deps ~p ~prev_status ~prompt ~response
    ~base ~name (r : Verifier.result_ok) =
  let st = List.assoc_opt p.Property.id r.by_property in
  let regr = regressed ~prev_status ~result:r in
  if st = Some `Established && not regr then begin
    let _ = Gap_branch.merge ~workdir:deps.workdir ~base ~name in
    let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
      ~property_id:p.id ~prompt ~response ~outcome:"applied" in
    let p2 = Property.regen_risk
               (Property.with_status p `Established) in
    log_outcome deps.logger "gap-step.accept" p2 [];
    Accepted p2
  end else begin
    Gap_branch.discard ~workdir:deps.workdir ~base ~name;
    let reason =
      if regr then "patch regressed an established property"
      else "verifier did not establish the focus property" in
    let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
      ~property_id:p.id ~prompt ~response ~outcome:"rejected" in
    let p2 = Property.bump_failure p in
    log_outcome deps.logger "gap-step.reject" p2
      [ "reason", `String reason ];
    Rejected (p2, reason)
  end

let try_apply_and_verify ~deps ~p ~prev_status ~prompt ~response_text =
  match Diff_extract.extract_diff response_text with
  | None -> on_no_diff ~deps ~p ~prompt ~response:response_text
  | Some diff ->
      let base = Git.current_branch ~cwd:deps.workdir in
      let name = Gap_branch.create ~workdir:deps.workdir
                   ~property_id:p.Property.id in
      Sigint.register_cleanup (fun () ->
        if Sys.file_exists deps.workdir then begin
          let _ = Git.checkout ~cwd:deps.workdir ~name:base in
          let _ = Git.delete_branch ~cwd:deps.workdir ~name in ()
        end);
      (match Git.apply_diff ~cwd:deps.workdir ~diff with
       | Error e ->
           on_apply_fail ~deps ~p ~prompt ~response:response_text
             ~base ~name e
       | Ok () ->
           let _ = Git.commit_all ~cwd:deps.workdir
             ~message:("k4k gap-step " ^ p.Property.id) in
           match deps.verifier_run ~workdir:deps.workdir
                   ~focus:[p.Property.id] with
           | `Tool_error msg ->
               on_verifier_error ~deps ~p ~prompt
                 ~response:response_text ~base ~name msg
           | `Ok r ->
               on_verifier_ok ~deps ~p ~prev_status ~prompt
                 ~response:response_text ~base ~name r)

let select_or_block ~deps gap =
  match Property.argmax_lex gap with
  | None -> `Empty
  | Some p when p.Property.blocked || p.failure_count >= 3 ->
      log_outcome deps.logger "gap-step.blocked" p [];
      `Blocked p
  | Some p -> `Pick p

let dispatch_response ~deps ~p ~prev_status ~prompt = function
  | `Budget_exhausted -> Budget_exhausted
  | `Tool_error msg ->
      let _ = persist_agent_run ~k4k_dir:deps.k4k_dir
        ~property_id:p.Property.id ~prompt ~response:""
        ~outcome:"tool-error" in
      let p2 = Property.bump_failure p in
      log_outcome deps.logger "gap-step.reject" p2
        [ "reason", `String ("agent: " ^ msg) ];
      Rejected (p2, "agent: " ^ msg)
  | `Ok (r : Agent_backend.response) ->
      deps.budget_remaining :=
        max 0 (!(deps.budget_remaining) - r.budget_used);
      try_apply_and_verify ~deps ~p ~prev_status ~prompt
        ~response_text:r.text

let step ~deps ~d ~current_summary ~prev_status (gap : Property.t list)
    : outcome =
  Sigint.raise_if_needed ();
  Gap_branch.preflight ~workdir:deps.workdir;
  match select_or_block ~deps gap with
  | `Empty -> Budget_exhausted
  | `Blocked p -> Blocked p
  | `Pick p ->
      let prompt = Gap_prompt.compose p d ~current_summary in
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
