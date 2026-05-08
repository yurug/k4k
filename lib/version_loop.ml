(** [Version_loop] — drives the per-version state machine and the
    direct-commit gap-step loop on top of it (ADR-011 §6, ADR-013 §2,
    v2 batch 4a/4b). Finalize / merge / tag delegated to
    [Version_finalize]; tradeoff retry to [Version_tradeoff]; sign-off
    polling to [Tradeoff_flow]. *)

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

let to_v_cfg (cfg : config) : Version_tradeoff.cfg_v = {
  cwd = cfg.cwd;
  k4k_dir = cfg.k4k_dir;
  emit = cfg.emit;
  agent_invoke = cfg.agent_invoke;
  verifier_run = cfg.verifier_run;
  budget = cfg.budget;
  file_path = cfg.file_path;
}

let logger_for cfg : Logger.t =
  let jsonl = Filename.concat cfg.k4k_dir "log.jsonl" in
  Logger.create ~verbosity:`Quiet ~jsonl_path:(Some jsonl)

let mk_deps cfg ~tier ~budget_ref ~logger : unit Gap_step.deps = {
  k4k_dir = cfg.k4k_dir;
  workdir = cfg.cwd;
  agent_invoke = cfg.agent_invoke;
  verifier_run = cfg.verifier_run;
  logger;
  budget_remaining = budget_ref;
  agent_backend = ();
  tier;
}

let on_accepted ~cfg ~prev_status ~prev_outcomes ~tier_assignments
    q tier commit_sha =
  cfg.emit "version.commit"
    (`Assoc [ "property_id", `String q.Property.id;
              "tier", `String (match tier with
                | `A -> "A" | `B -> "B" | `C -> "C");
              "sha", `String commit_sha ]);
  prev_status := (q.Property.id, `Established) :: !prev_status;
  prev_outcomes := { Version_finalize.id = q.id;
                     status = "established";
                     commit_sha = Some commit_sha }
                   :: !prev_outcomes;
  tier_assignments := (q.Property.id, tier) :: !tier_assignments

let on_deferred ~cfg ~prev_outcomes q =
  cfg.emit "version.deferred"
    (`Assoc [ "property_id", `String q.Property.id ]);
  prev_outcomes := { Version_finalize.id = q.id;
                     status = "deferred"; commit_sha = None }
                   :: !prev_outcomes

let drive_property_full ~deps_a ~d ~cfg ~v_number
    ~prev_status ~prev_outcomes ~tier_assignments ?cotype p =
  match Version_tradeoff.drive_at_tier ~deps:deps_a ~d ~prev_status p with
  | `Accepted (q, commit_sha) ->
      on_accepted ~cfg ~prev_status ~prev_outcomes
        ~tier_assignments q `A commit_sha;
      `Continue
  | `Done_blocked q ->
      on_deferred ~cfg ~prev_outcomes q; `Skip
  | `Stop -> `Stop
  | `Tradeoff (q, reason) ->
      let v_cfg = to_v_cfg cfg in
      (match Version_tradeoff.handle ~cfg:v_cfg ~v_number ~d
               ~prev_status ?cotype q reason with
       | `Accepted_at (tier, q', sha) ->
           on_accepted ~cfg ~prev_status ~prev_outcomes
             ~tier_assignments q' tier sha;
           `Continue
       | `Defer q' ->
           on_deferred ~cfg ~prev_outcomes q'; `Skip
       | `Stop -> `Stop)

let ue_cfg cfg : Version_user_edits.cfg =
  { cwd = cfg.cwd; emit = cfg.emit; file_path = cfg.file_path }

let rec run_gap_loop ~deps_a ~d ~cfg ~v_number ~prev_status ~prev_outcomes
    ~tier_assignments ~baseline_user_hashes ~surfaced_edits ?cotype pending =
  let _ = Version_user_edits.check_and_queue
            ~cfg:(ue_cfg cfg) ~v_number
            ~baseline:baseline_user_hashes ~surfaced:surfaced_edits
            ?cotype () in
  match Property.argmax_lex pending with
  | None -> ()
  | Some p ->
      let rest = List.filter
        (fun (q : Property.t) -> q.id <> p.id) pending in
      (match drive_property_full ~deps_a ~d ~cfg ~v_number
               ~prev_status ~prev_outcomes ~tier_assignments ?cotype p with
       | `Stop -> ()
       | `Continue | `Skip ->
           run_gap_loop ~deps_a ~d ~cfg ~v_number ~prev_status
             ~prev_outcomes ~tier_assignments
             ~baseline_user_hashes ~surfaced_edits ?cotype rest)

let persist_initial ~cfg ~v ~d =
  Version_persist.ensure_dirs ~k4k_dir:cfg.k4k_dir
    ~number:v.Version.number;
  Version_persist.write_d_spec ~k4k_dir:cfg.k4k_dir
    ~number:v.Version.number ~d;
  Version_persist.write_manifest ~k4k_dir:cfg.k4k_dir ~v ()

let mk_developing_status n =
  { Inline_blocks.version_n = n;
    state = "developing";
    tier_dist = { tier_a = 0; tier_b = 0; tier_c = 0 };
    pending_user_edits = 0;
    last_activity = Inline_blocks.timestamp_now ();
    open_tradeoffs = 0; }

let write_developing_status ~cfg ~v ?cotype () =
  match cfg.file_path, cotype with
  | Some fp, Some ct ->
      let block = Inline_blocks.render_status
        (mk_developing_status v.Version.number) in
      Version_user_edits.splice_status_block
        ~cotype:ct ~file_path:fp ~status_block:block;
      let clean, _ = Git.is_clean ~cwd:cfg.cwd in
      if not clean then
        let _ = Git.commit_all ~cwd:cfg.cwd
                  ~message:"[k4k] status: developing" in ()
  | _ -> ()

let to_local_result : Version_finalize.result -> result = function
  | Version_finalize.Done { tag; tier_dist } -> Done { tag; tier_dist }
  | Version_finalize.Rolled_back -> Rolled_back

let drive_version ~cfg ~d v ~started_at ?cotype () : result =
  persist_initial ~cfg ~v ~d;
  write_developing_status ~cfg ~v ?cotype ();
  let baseline_user_hashes =
    Version_user_edits.snapshot ?cotype ~file_path:cfg.file_path () in
  let surfaced_edits = ref 0 in
  let logger = logger_for cfg in
  let budget_ref = ref cfg.budget in
  let deps_a = mk_deps cfg ~tier:`A ~budget_ref ~logger in
  let gap = Property.from_characterization d in
  let prev_status = ref [] in
  let prev_outcomes = ref [] in
  let tier_assignments = ref [] in
  run_gap_loop ~deps_a ~d ~cfg ~v_number:v.Version.number
    ~prev_status ~prev_outcomes ~tier_assignments
    ~baseline_user_hashes ~surfaced_edits ?cotype gap;
  let outcomes = List.rev !prev_outcomes in
  Version_persist.write_tiers
    ~k4k_dir:cfg.k4k_dir ~number:v.Version.number
    ~tiers:(List.rev !tier_assignments);
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
