(** [Watcher_loop] — the watcher's main loop. See [.mli]. *)

type config = {
  file_path        : string;
  k4k_dir          : string;
  verbosity        : [ `Quiet | `Verbose | `Debug ];
  exit_on_stable   : bool;
  exit_on_done     : bool;
  max_versions     : int option;
  poll_interval_ms : int;
  emit             : string -> Yojson.Safe.t -> unit;
}

let cotype_handle () = Cotype.create Cotype.default_config

let read_file_via_cotype ct ~file =
  try Some (Cotype.read_base ct ~file)
  with Error.K4k_error _ -> None

let stability_of_text ~content =
  try
    let parsed = Parser.parse content in
    match Stability.check_structural parsed with
    | Stability.Stable -> `Stable parsed
    | Stability.Unstable issues -> `Unstable issues
  with Error.K4k_error e ->
    `Unstable [ Error.issue ~section:"parse"
                  (Error.code_id e ^ ": " ^ Error.render e) ]

let questions_of_issues (issues : Error.issue list) : string list =
  List.map (fun (i : Error.issue) ->
    Printf.sprintf "%s: %s" i.section i.details) issues

(* axis-4 L3: surface cotype-write failures via JSONL rather than
   silently dropping them. *)
let append_clarification cfg ct ~issues =
  try
    Cotype.append_clarification ct ~path:cfg.file_path
      ~questions:(questions_of_issues issues);
    cfg.emit "clarification.appended"
      (`Assoc [ "count", `Int (List.length issues) ])
  with Error.K4k_error e ->
    cfg.emit "clarification.write_failed"
      (`Assoc [ "code", `String (Error.code_id e);
                "render", `String (Error.render e) ])

let render_and_save_status cfg ct ~status_block =
  Version_user_edits.splice_status_block
    ~cotype:ct ~file_path:cfg.file_path ~status_block

let user_directives_in_file cfg ct =
  match read_file_via_cotype ct ~file:cfg.file_path with
  | None -> []
  | Some content ->
      let parsed =
        try Some (Parser.parse content) with _ -> None
      in
      match parsed with
      | None -> []
      | Some p ->
          List.fold_left (fun acc (s : Parser.section) ->
            if s.id = "k4k-status" then
              acc @ Inline_blocks.parse_directives s.content
            else acc) [] p.sections

let mk_status ~version_n ~state ~last_act =
  let open Inline_blocks in
  { version_n; state;
    tier_dist = { tier_a = 0; tier_b = 0; tier_c = 0 };
    pending_user_edits = 0; last_activity = last_act;
    open_tradeoffs = 0; }

let now_iso () = Inline_blocks.timestamp_now ()

let sleep_ms ms =
  let s = float_of_int ms /. 1000.0 in
  ignore (Unix.select [] [] [] s)

let process_unstable cfg ct issues =
  append_clarification cfg ct ~issues;
  let s = mk_status ~version_n:1 ~state:"refining" ~last_act:(now_iso ()) in
  render_and_save_status cfg ct
    ~status_block:(Inline_blocks.render_status s);
  cfg.emit "stability.unstable"
    (`Assoc [ "issues", `Int (List.length issues) ])

(* On stable: file-pruning (ADR-011 §7); idempotent. The
   developing-status splice happens inside [Version_loop] after
   start_new (batch 4b). *)
let process_stable cfg ct =
  Watcher_prune.run ~ct ~file_path:cfg.file_path
    ~k4k_dir:cfg.k4k_dir ~emit:cfg.emit;
  cfg.emit "stability.pass" (`Assoc [])

let attempt_version cfg ct ~agent_invoke =
  match Watcher_dev.try_run_version ~file_path:cfg.file_path
          ~k4k_dir:cfg.k4k_dir ~emit:cfg.emit ~agent_invoke ct with
  | `Done ->
      let n = max 1 (Version_persist.next_version_number
                       ~k4k_dir:cfg.k4k_dir - 1) in
      Watcher_dev.after_version_done ~file_path:cfg.file_path ct
        ~version_n:n
        ~tier_dist:{ tier_a = 0; tier_b = 0; tier_c = 0 };
      `Done
  | `Rolled_back -> `Rolled_back
  | `Skipped -> `Skipped

let on_rollback cfg ct =
  Watcher_dev.on_user_rollback_directive ~ct
    ~file_path:cfg.file_path ~k4k_dir:cfg.k4k_dir
    ~emit:cfg.emit
    ~render_and_save_status:(render_and_save_status cfg ct)

(* On every stable tick, attempt a version. The idempotence gate
   inside [Watcher_dev.try_run_version] makes this cheap on idle
   specs. [rollback_streak] resets on [`Done] and bumps on
   [`Rolled_back]; crossing [Rollback_feedback.streak_threshold]
   escalates (Ralph-loop step 3). *)
let on_stable cfg ct ~stable_seen ~versions_done ~rollback_streak
    ~agent_invoke =
  if not stable_seen then process_stable cfg ct;
  if cfg.exit_on_stable then `Stop
  else
    let outcome = attempt_version cfg ct ~agent_invoke in
    let terminal = outcome = `Done || outcome = `Rolled_back in
    if terminal then incr versions_done;
    (match outcome with
     | `Done -> rollback_streak := 0
     | `Rolled_back ->
         incr rollback_streak;
         if !rollback_streak = Rollback_feedback.streak_threshold then
           Rollback_feedback.escalate_unsatisfiable_streak
             ~ct ~file_path:cfg.file_path ~emit:cfg.emit
             ~streak:!rollback_streak
     | `Skipped -> ());
    let cap_hit = match cfg.max_versions with
      | Some m -> !versions_done >= m | None -> false
    in
    if (cfg.exit_on_done && terminal) || cap_hit then `Stop
    else (sleep_ms cfg.poll_interval_ms; `Continue true)

let on_unstable cfg ct issues ~stable_seen =
  process_unstable cfg ct issues;
  if cfg.exit_on_stable then `Stop
  else (sleep_ms cfg.poll_interval_ms; `Continue stable_seen)

let process_directives cfg ct directives ~stable_seen =
  if List.mem `Rollback directives then begin
    cfg.emit "directive.rollback" (`Assoc []);
    on_rollback cfg ct; `Stop
  end else if List.mem `Pause directives then begin
    cfg.emit "directive.pause" (`Assoc []);
    sleep_ms cfg.poll_interval_ms; `Continue stable_seen
  end else `No_directive

let one_tick cfg ct ~stable_seen ~versions_done ~rollback_streak
    ~agent_invoke =
  if Sigint.should_exit () then `Stop
  else begin
    let directives = user_directives_in_file cfg ct in
    match process_directives cfg ct directives ~stable_seen with
    | `Stop -> `Stop
    | `Continue s -> `Continue s
    | `No_directive ->
        match read_file_via_cotype ct ~file:cfg.file_path with
        | None -> sleep_ms cfg.poll_interval_ms; `Continue stable_seen
        | Some content ->
            (match stability_of_text ~content with
             | `Unstable issues -> on_unstable cfg ct issues ~stable_seen
             | `Stable _ ->
                 on_stable cfg ct ~stable_seen ~versions_done
                   ~rollback_streak ~agent_invoke)
  end

let run cfg : int =
  cfg.emit "watcher.start"
    (`Assoc [ "file", `String cfg.file_path ]);
  let ct = cotype_handle () in
  (* Cotype init can fail if cotype isn't installed; emit and exit. *)
  (match Cotype.ensure_init ct ~file:cfg.file_path with
   | Ok () -> ()
   | Error msg ->
       cfg.emit "cotype.unavailable" (`Assoc [ "error", `String msg ]);
       output_string stderr (Printf.sprintf "k4k: cotype: %s\n" msg);
       flush stderr);
  let stable = ref false in
  let versions_done = ref 0 in
  let rollback_streak = ref 0 in
  (* Resolve once; canned-backend queues must persist across ticks. *)
  let agent_invoke =
    Watcher_dev.resolve_invoke ~emit:cfg.emit ~k4k_dir:cfg.k4k_dir in
  let rec loop () =
    match one_tick cfg ct ~stable_seen:!stable ~versions_done
            ~rollback_streak ~agent_invoke with
    | `Stop -> ()
    | `Continue s -> stable := s; loop ()
  in
  loop ();
  cfg.emit "watcher.exit" (`Assoc []);
  0
