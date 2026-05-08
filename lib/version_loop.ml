(** [Version_loop] — drives the per-version state machine and the
    direct-commit gap-step loop on top of it (ADR-011 §6, ADR-013 §2,
    v2 batch 4a). Finalize / merge / tag delegated to
    [Version_finalize]. *)

type agent_invoke =
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result

type verifier_run =
  workdir:string ->
  focus:string list ->
  Verifier.run_result

type config = {
  cwd          : string;
  k4k_dir      : string;
  default_branch : string;
  emit         : string -> Yojson.Safe.t -> unit;
  delete_branch_on_done : bool;
  agent_invoke : agent_invoke;
  verifier_run : verifier_run;
  budget       : int;
  tier         : [ `A | `B | `C ];
  file_path    : string option;
}

type result =
  | Done of { tag : string; tier_dist : Inline_blocks.tier_distribution }
  | Rolled_back

let logger_for cfg : Logger.t =
  let jsonl = Filename.concat cfg.k4k_dir "log.jsonl" in
  Logger.create ~verbosity:`Quiet ~jsonl_path:(Some jsonl)

let mk_deps cfg ~budget_ref ~logger : unit Gap_step.deps = {
  k4k_dir = cfg.k4k_dir;
  workdir = cfg.cwd;
  agent_invoke = cfg.agent_invoke;
  verifier_run = cfg.verifier_run;
  logger;
  budget_remaining = budget_ref;
  agent_backend = ();
  tier = cfg.tier;
}

let summarize_s prev =
  let n = List.length prev in
  Printf.sprintf "(%d propert%s already established)" n
    (if n = 1 then "y" else "ies")

let on_accepted ~cfg ~prev_status ~prev_outcomes q commit_sha =
  cfg.emit "version.commit"
    (`Assoc [ "property_id", `String q.Property.id;
              "sha", `String commit_sha ]);
  prev_status := (q.Property.id, `Established) :: !prev_status;
  prev_outcomes := { Version_finalize.id = q.id;
                     status = "established";
                     commit_sha = Some commit_sha }
                   :: !prev_outcomes

let on_deferred ~cfg ~prev_outcomes q =
  cfg.emit "version.deferred"
    (`Assoc [ "property_id", `String q.Property.id ]);
  prev_outcomes := { Version_finalize.id = q.id;
                     status = "deferred"; commit_sha = None }
                   :: !prev_outcomes

let drive_property ~deps ~d ~cfg ~prev_status ~prev_outcomes p =
  let summary = summarize_s !prev_status in
  let o = Gap_step.step ~deps ~d
            ~current_summary:summary
            ~prev_status:!prev_status ~property:p in
  match o with
  | Gap_step.Accepted { property = q; commit_sha } ->
      on_accepted ~cfg ~prev_status ~prev_outcomes q commit_sha;
      `Continue
  | Gap_step.Rejected { property = q; reason } ->
      cfg.emit "version.reject"
        (`Assoc [ "property_id", `String q.Property.id;
                  "reason", `String reason ]);
      `Retry q
  | Gap_step.Blocked q | Gap_step.Tradeoff { property = q } ->
      on_deferred ~cfg ~prev_outcomes q;
      `Skip
  | Gap_step.Budget_exhausted ->
      cfg.emit "version.budget_exhausted" (`Assoc []);
      `Stop

let rec drive_with_retries ~deps ~d ~cfg ~prev_status ~prev_outcomes p =
  if Sigint.should_exit () then `Stop
  else
    match drive_property ~deps ~d ~cfg ~prev_status ~prev_outcomes p with
    | (`Continue | `Skip | `Stop) as r -> r
    | `Retry q ->
        if q.Property.failure_count >= 3 then begin
          prev_outcomes := { Version_finalize.id = q.id;
                             status = "deferred"; commit_sha = None }
                           :: !prev_outcomes;
          `Skip
        end
        else drive_with_retries ~deps ~d ~cfg ~prev_status
               ~prev_outcomes q

let rec run_gap_loop ~deps ~d ~cfg ~prev_status ~prev_outcomes pending =
  match Property.argmax_lex pending with
  | None -> ()
  | Some p ->
      let rest = List.filter
        (fun (q : Property.t) -> q.id <> p.id) pending in
      (match drive_with_retries ~deps ~d ~cfg ~prev_status
              ~prev_outcomes p with
       | `Stop -> ()
       | `Continue | `Skip ->
           run_gap_loop ~deps ~d ~cfg ~prev_status
             ~prev_outcomes rest)

let persist_initial ~cfg ~v ~d =
  Version_persist.ensure_dirs ~k4k_dir:cfg.k4k_dir
    ~number:v.Version.number;
  Version_persist.write_d_spec ~k4k_dir:cfg.k4k_dir
    ~number:v.Version.number ~d;
  Version_persist.write_manifest ~k4k_dir:cfg.k4k_dir ~v ()

(* v2 batch 4b: write a "developing" status block on the version branch
   via cotype, then commit so the gap-step preflight clean-tree check
   passes. Best-effort: failures are swallowed (the gap loop will still
   surface its own preflight errors). *)
let mk_developing_status n =
  { Inline_blocks.version_n = n;
    state = "developing";
    tier_dist = { tier_a = 0; tier_b = 0; tier_c = 0 };
    pending_user_edits = 0;
    last_activity = Inline_blocks.timestamp_now ();
    open_tradeoffs = 0; }

let save_status ~cotype ~file_path ~status_block =
  try
    let opened = Cotype.open_ cotype ~file:file_path in
    match opened with
    | Error _ -> ()
    | Ok r ->
        let base = Persist.read_file r.base_path in
        let merged = Status_splice.replace_or_append base status_block in
        let _ = Cotype.save cotype ~file:file_path
                  ~base_sha:r.base_sha ~actor:"agent:k4k"
                  ~bytes:merged in ()
  with _ -> ()

let commit_status_on_branch ~cwd =
  let clean, _ = Git.is_clean ~cwd in
  if not clean then
    let _ = Git.commit_all ~cwd
              ~message:"[k4k] status: developing" in ()

let write_developing_status ~cfg ~v ?cotype () =
  match cfg.file_path, cotype with
  | Some fp, Some ct ->
      let block = Inline_blocks.render_status
        (mk_developing_status v.Version.number) in
      save_status ~cotype:ct ~file_path:fp ~status_block:block;
      commit_status_on_branch ~cwd:cfg.cwd
  | _ -> ()

let to_local_result : Version_finalize.result -> result = function
  | Version_finalize.Done { tag; tier_dist } -> Done { tag; tier_dist }
  | Version_finalize.Rolled_back -> Rolled_back

let drive_version ~cfg ~d v ~started_at ?cotype () : result =
  persist_initial ~cfg ~v ~d;
  write_developing_status ~cfg ~v ?cotype ();
  let logger = logger_for cfg in
  let budget_ref = ref cfg.budget in
  let deps = mk_deps cfg ~budget_ref ~logger in
  let gap = Property.from_characterization d in
  let prev_status = ref [] in
  let prev_outcomes = ref [] in
  run_gap_loop ~deps ~d ~cfg ~prev_status ~prev_outcomes gap;
  let outcomes = List.rev !prev_outcomes in
  to_local_result
    (Version_finalize.finalize
       ~cwd:cfg.cwd ~k4k_dir:cfg.k4k_dir
       ~default_branch:cfg.default_branch
       ~delete_branch:cfg.delete_branch_on_done
       ~emit:cfg.emit ~v ~outcomes ~started_at ?cotype ())

let run ~cfg ~baseline_sha ~d ?cotype () : result =
  let number = Version_persist.next_version_number ~k4k_dir:cfg.k4k_dir in
  cfg.emit "version.start"
    (`Assoc [ "version", `Int number;
              "baseline_sha", `String baseline_sha;
              "d_hash", `String d.Characterization.hash ]);
  match Version.start_new ~cwd:cfg.cwd ~number
          ~baseline_sha ~d_hash:d.hash with
  | Error e ->
      cfg.emit "version.start_error" (`Assoc [ "error", `String e ]);
      Rolled_back
  | Ok v ->
      let started_at = v.started_at in
      drive_version ~cfg ~d v ~started_at ?cotype ()
