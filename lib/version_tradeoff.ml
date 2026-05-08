(** [Version_tradeoff] — extracted from [Version_loop] (200-line cap):
    composes a [Tradeoff_flow.proposal] from a Tier-A failure, drives
    sign-off polling, retries the gap-step at the new tier on
    approval, or retries at Tier-A with guidance on rejection. *)

type cfg_v = {
  cwd          : string;
  k4k_dir      : string;
  emit         : string -> Yojson.Safe.t -> unit;
  agent_invoke :
    purpose:Agent_backend.purpose ->
    prompt:string -> budget:int -> Agent_backend.result;
  verifier_run :
    workdir:string -> focus:string list -> Verifier.run_result;
  budget       : int;
  file_path    : string option;
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

let propose ~cfg ~v_number ?cotype p reason =
  match cotype, cfg.file_path with
  | Some ct, Some fp ->
      let proposal : Tradeoff_flow.proposal = {
        property_id = p.Property.id;
        why_a_failed = reason;
        proposed_tier = `B;
        whats_lost =
          "machine-checked guarantee replaced by exhaustive testing";
        whats_gained =
          "the property is established under Tier-B verification";
      } in
      Some (Tradeoff_flow.propose_and_wait
              ~cotype:ct ~file_path:fp
              ~k4k_dir:cfg.k4k_dir ~version_n:v_number
              ~emit:cfg.emit ~proposal)
  | _ -> None

let reset_for_tier (p : Property.t) =
  { p with failure_count = 0; blocked = false; status = `Required }

let summarize_s prev =
  let n = List.length prev in
  Printf.sprintf "(%d propert%s already established)" n
    (if n = 1 then "y" else "ies")

let drive_one_step ~deps ~d ~prev_status p =
  let summary = summarize_s !prev_status in
  Gap_step.step ~deps ~d ~current_summary:summary
    ~prev_status:!prev_status ~property:p

(** Drive a property at a single tier, retrying on rejection until
    accepted, blocked, or 3-strikes [Tradeoff]. Returns one of:
    [`Accepted r] / [`Done_blocked q] / [`Tradeoff (q, reason)] / [`Stop]. *)
let rec drive_at_tier ~deps ~d ~prev_status p =
  if Sigint.should_exit () then `Stop
  else
    match drive_one_step ~deps ~d ~prev_status p with
    | Gap_step.Accepted { property = q; commit_sha } ->
        `Accepted (q, commit_sha)
    | Gap_step.Rejected { property = q; _ } ->
        if q.failure_count >= 3 then `Done_blocked q
        else drive_at_tier ~deps ~d ~prev_status q
    | Gap_step.Blocked q -> `Done_blocked q
    | Gap_step.Tradeoff { property = q } ->
        `Tradeoff (q, "Tier-A failed after 3 attempts")
    | Gap_step.Budget_exhausted -> `Stop

(** Outcome of [run_for_property]:
    - [`Accepted_at (tier, q, sha)] — the property converged at [tier]
    - [`Defer q] — the property is deferred (blocked/timed-out)
    - [`Stop] — budget/SIGINT exit *)
type 'k outcome =
  [ `Accepted_at of [ `A | `B | `C ] * Property.t * string
  | `Defer of Property.t
  | `Stop ]
constraint 'k = unit

let drive_at_new_tier ~cfg ~d ~prev_status ~tier p =
  let logger = logger_for cfg in
  let budget_ref = ref cfg.budget in
  let deps = mk_deps cfg ~tier ~budget_ref ~logger in
  match drive_at_tier ~deps ~d ~prev_status p with
  | `Accepted (q, commit_sha) ->
      `Accepted_at (tier, q, commit_sha)
  | `Done_blocked q | `Tradeoff (q, _) -> `Defer q
  | `Stop -> `Stop

(* Tradeoff_flow.propose_and_wait mutates the user's [.k4k] file twice
   (proposal splice, then archive-and-breadcrumb on resolution). Those
   modifications land on the version branch's working tree, leaving it
   dirty. Gap_step.preflight refuses to run on a dirty tree, so any
   retry — at the approved tier, at Tier-A with guidance, or simply
   the next property after a deferral — would crash with
   ESTATE_CORRUPT. We commit the residue here, on the version branch,
   so the next preflight starts from a clean slate. *)
let commit_tradeoff_residue ~cwd ~property_id ~label =
  let clean, _ = Git.is_clean ~cwd in
  if not clean then
    let msg = Printf.sprintf "[k4k] tradeoff %s: %s" label property_id in
    let _ = Git.commit_all ~cwd ~message:msg in ()

(** [handle ~cfg ~v_number ~d ~prev_status ?cotype p_failed reason]
    — open a tradeoff proposal for [p_failed], wait for the user's
    reply, then either retry the property at the approved tier or at
    Tier-A with the user's guidance. *)
let handle ~cfg ~v_number ~d ~prev_status ?cotype p_failed reason
    : unit outcome =
  match propose ~cfg ~v_number ?cotype p_failed reason with
  | None ->
      `Defer p_failed
  | Some Tradeoff_flow.Timed_out ->
      commit_tradeoff_residue ~cwd:cfg.cwd
        ~property_id:p_failed.Property.id ~label:"timed-out";
      `Defer p_failed
  | Some (Tradeoff_flow.Rejected guidance) ->
      cfg.emit "tradeoff.rejected"
        (`Assoc [ "property_id", `String p_failed.Property.id;
                  "guidance", `String guidance ]);
      commit_tradeoff_residue ~cwd:cfg.cwd
        ~property_id:p_failed.Property.id ~label:"rejected";
      let p_reset = reset_for_tier p_failed in
      drive_at_new_tier ~cfg ~d ~prev_status ~tier:`A p_reset
  | Some (Tradeoff_flow.Approved tier) ->
      cfg.emit "tradeoff.approved"
        (`Assoc [ "property_id", `String p_failed.Property.id;
                  "tier", `String (match tier with
                    | `B -> "B" | `C -> "C") ]);
      let label = match tier with
        | `B -> "approved-tier-b" | `C -> "approved-tier-c" in
      commit_tradeoff_residue ~cwd:cfg.cwd
        ~property_id:p_failed.Property.id ~label;
      let p_reset = reset_for_tier p_failed in
      let tier_abc : [ `A | `B | `C ] = match tier with
        | `B -> `B | `C -> `C in
      drive_at_new_tier ~cfg ~d ~prev_status ~tier:tier_abc p_reset
