(** [Run_loop] — the step-3 top-level convergence loop.

    Wraps [Full_check.run] (semantic stability + D persistence) and the
    iterative [Gap_step.step] driver. Re-reads the file at the start of
    every step (P13). Honors [--max-steps] and [--budget]. Persists
    [.k4k/gap/properties.json] after every successful update. *)

type config = {
  max_steps : int;
  budget    : int;        (* hard cap; overrides manifest if > 0 *)
  between_steps : (unit -> unit) option;
    (* Test hook: invoked between gap-steps. Used by T4 to mutate
       [<file.k4k>] and verify the next iteration re-runs stability. *)
}

type result = {
  steps_run : int;
  final_gap : Property.t list;
  converged : bool;
}

let default_config =
  { max_steps = 50; budget = 1000; between_steps = None }

let initial_summary _d =
  "(no current source summary; gap-step is the first iteration)"

let prev_status_of_props (ps : Property.t list)
    : (string * Verifier.status) list =
  List.filter_map (fun (p : Property.t) ->
    match p.status with
    | `Established -> Some (p.id, `Established)
    | `Contradicted -> Some (p.id, `Contradicted)
    | `Unknown | `Required -> None) ps

let persist_gap ~k4k_dir (ps : Property.t list) =
  let bytes = Canonical_json.to_string
                (Property_json.list_to_yojson ps) in
  Persist.write_gap ~k4k_dir ~bytes

let update_gap ~accepted ~rejected (ps : Property.t list)
    : Property.t list =
  let updated =
    List.map (fun (p : Property.t) ->
      match accepted with
      | Some a when a.Property.id = p.id -> a
      | _ ->
          (match rejected with
           | Some r when r.Property.id = p.id -> r
           | _ -> p)) ps
  in
  (* Drop accepted (=Established) entries from the gap list. *)
  List.filter (fun (p : Property.t) ->
    p.status <> `Established) updated

let drive_one ~deps ~d ~current_summary ~prev_status ~gap =
  match Gap_step.step ~deps ~d ~current_summary ~prev_status gap with
  | Accepted q -> `Accepted q
  | Rejected (q, _) -> `Rejected q
  | Blocked _ -> `Blocked
  | Budget_exhausted -> `Budget

let raise_max_steps n =
  raise (Error.K4k_error (Error.E_max_steps n))

let raise_budget ~used ~cap =
  raise (Error.K4k_error (Error.E_budget { used; cap }))

let loop_iter ~deps ~d ~cfg ~k4k_dir ~logger ~step_no ~window
    ~prev_status (gap : Property.t list) =
  if !step_no >= cfg.max_steps then raise_max_steps cfg.max_steps;
  incr step_no;
  Logger.info logger "loop.step"
    (`Assoc [ "n", `Int !step_no;
              "gap_count", `Int (List.length gap) ]);
  let current_summary = initial_summary d in
  let t0 = Unix.gettimeofday () in
  let outcome =
    drive_one ~deps ~d ~current_summary ~prev_status ~gap in
  let dt = Unix.gettimeofday () -. t0 in
  window := Tty_status.push_duration !window dt;
  (match cfg.between_steps with None -> () | Some f -> f ());
  match outcome with
  | `Accepted q ->
      let new_gap = update_gap ~accepted:(Some q) ~rejected:None gap in
      persist_gap ~k4k_dir new_gap;
      Kb_regen.regen ~k4k_dir ~prev_d:None ~current_d:d ~logger;
      `Continue (new_gap, prev_status @ [(q.id, `Established)])
  | `Rejected q ->
      let new_gap = update_gap ~accepted:None ~rejected:(Some q) gap in
      persist_gap ~k4k_dir new_gap;
      `Continue (new_gap, prev_status)
  | `Blocked ->
      `Continue (gap, prev_status)
  | `Budget ->
      let cap = cfg.budget in
      let used = max 0 (cap - !(deps.Gap_step.budget_remaining)) in
      raise_budget ~used ~cap

let run ~deps ~d ~cfg ~k4k_dir ~logger
    ~initial_gap : result =
  persist_gap ~k4k_dir initial_gap;
  Kb_regen.regen_full ~k4k_dir ~current_d:d ~logger;
  let gap = ref initial_gap in
  let prev = ref (prev_status_of_props initial_gap) in
  let step_no = ref 0 in
  let window = ref (Tty_status.empty_window ()) in
  let go = ref true in
  while !go && !gap <> [] do
    match loop_iter ~deps ~d ~cfg ~k4k_dir ~logger ~step_no
            ~window ~prev_status:!prev !gap with
    | `Continue (g', p') ->
        gap := g'; prev := p';
        if List.for_all (fun (p : Property.t) ->
             p.blocked) !gap then go := false
  done;
  Logger.info logger "loop.done"
    (`Assoc [ "steps", `Int !step_no;
              "remaining", `Int (List.length !gap) ]);
  { steps_run = !step_no;
    final_gap = !gap;
    converged = !gap = [] }
