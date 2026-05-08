(** [Version_tradeoff] — tradeoff sign-off + retry orchestration,
    extracted from [Version_loop] (200-line cap).

    @invariant P21 — the proposal is opened only AFTER a Tier-A
                     attempt failed 3×; retries happen at the user-
                     approved tier (or Tier-A again with guidance). *)

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

(** Internal: [drive_at_tier ~deps ~d ~prev_status p] runs a property
    at one tier until accept/block/3-strike-tradeoff. Exposed so the
    [Version_loop] loop can run the initial Tier-A pass through the
    same code path. *)
val drive_at_tier :
  deps:unit Gap_step.deps ->
  d:Characterization.t ->
  prev_status:(string * Verifier.status) list ref ->
  Property.t ->
  [ `Accepted of Property.t * string  (* property + commit_sha *)
  | `Done_blocked of Property.t
  | `Tradeoff of Property.t * string
  | `Stop ]

(** Outcome of the tradeoff-driven retry. *)
type 'k outcome =
  [ `Accepted_at of [ `A | `B | `C ] * Property.t * string
  | `Defer of Property.t
  | `Stop ]
constraint 'k = unit

val handle :
  cfg:cfg_v ->
  v_number:int ->
  d:Characterization.t ->
  prev_status:(string * Verifier.status) list ref ->
  ?cotype:Cotype.t ->
  Property.t -> string -> unit outcome
