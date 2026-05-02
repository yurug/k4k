(** [Gap_branch] — git scratch-branch lifecycle for [Gap_step] per
    Q3.2. *)

(** [preflight ~workdir] — verify working tree is a git repo and clean.

    @raise Error.K4k_error E_state_corrupt otherwise. *)
val preflight : workdir:string -> unit

(** [create ~workdir ~property_id] — create and check out a fresh
    scratch branch named per Q3.2.

    @raise Error.K4k_error E_state_corrupt on name conflict or git
                                            failure. *)
val create : workdir:string -> property_id:string -> string

(** [discard ~workdir ~base ~name] — switch back to [base] and force-
    delete [name]. Errors are swallowed (best-effort cleanup). *)
val discard : workdir:string -> base:string -> name:string -> unit

(** [merge ~workdir ~base ~name] — switch to [base], FF-merge [name],
    delete [name]. Returns [Error] if merge fails. *)
val merge :
  workdir:string -> base:string -> name:string -> (unit, string) result
