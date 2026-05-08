(** [Watcher_loop] — the watcher's main loop. See [.mli]. *)

type config = {
  file_path        : string;
  k4k_dir          : string;
  verbosity        : [ `Quiet | `Verbose | `Debug ];
  exit_on_stable   : bool;
  exit_on_done     : bool;
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

let append_clarification cfg ct ~issues =
  try
    Cotype.append_clarification ct ~path:cfg.file_path
      ~questions:(questions_of_issues issues);
    cfg.emit "clarification.appended"
      (`Assoc [ "count", `Int (List.length issues) ])
  with Error.K4k_error _ -> ()

let render_and_save_status cfg ct ~status_block =
  try
    let opened = Cotype.open_ ct ~file:cfg.file_path in
    match opened with
    | Error _ -> ()
    | Ok r ->
        let base = Persist.read_file r.base_path in
        let merged = Status_splice.replace_or_append base status_block in
        let _ = Cotype.save ct ~file:cfg.file_path
                  ~base_sha:r.base_sha ~actor:"agent:k4k"
                  ~bytes:merged in
        ()
  with _ -> ()

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

(* Test-mode exit: under --exit-on-stable, return after the first
   state transition (stable OR unstable). Production loop never sets
   this. *)
let test_exit_now cfg = cfg.exit_on_stable

(* v2 batch 4b: do NOT mutate the working tree before [Version.start_new]
   runs. The status block is written from inside [Version_loop] after
   the version branch is created (so [Gap_step.preflight]'s clean-tree
   check passes without an intervening [k4k] snapshot commit). We still
   emit the JSONL event here for operator visibility. *)
let _process_stable_legacy_unused = ()
let process_stable cfg _ct =
  cfg.emit "stability.pass" (`Assoc [])

(* On a stable spec, try to drive the development half. When the test
   knob [K4K_TEST_D_PATH] is set we cut a version branch, run the
   accept-only gap loop, merge + tag, and (if [exit_on_done]) return.
   Production v2 batch 3 emits [version.skip] until batch 4 wires
   formalization. *)
let attempt_version cfg ct =
  match Watcher_dev.try_run_version ~file_path:cfg.file_path
          ~k4k_dir:cfg.k4k_dir ~emit:cfg.emit ct with
  | `Done ->
      let next_n = Version_persist.next_version_number
                     ~k4k_dir:cfg.k4k_dir - 1 in
      let n = max 1 next_n in
      Watcher_dev.after_version_done ~file_path:cfg.file_path ct
        ~version_n:n
        ~tier_dist:{ tier_a = 0; tier_b = 0; tier_c = 0 };
      `Done
  | `Pending -> `Pending

let on_rollback cfg ct =
  let cwd = Filename.dirname cfg.file_path in
  let default_branch = Git.default_branch ~cwd in
  let next_n = Version_persist.next_version_number
                 ~k4k_dir:cfg.k4k_dir - 1 in
  let n = max 1 next_n in
  let branch = Version.branch_name_of n in
  if Git.branch_exists ~cwd ~name:branch then begin
    let _ = Git.checkout ~cwd ~name:default_branch in
    let _ = Git.delete_branch ~cwd ~name:branch in
    cfg.emit "version.rolled_back"
      (`Assoc [ "version", `Int n;
                "branch", `String branch ])
  end;
  let s = mk_status ~version_n:n ~state:"rolled-back"
            ~last_act:(now_iso ()) in
  render_and_save_status cfg ct
    ~status_block:(Inline_blocks.render_status s)

let on_stable cfg ct ~stable_seen =
  if not stable_seen then process_stable cfg ct;
  if cfg.exit_on_stable then `Stop
  else if cfg.exit_on_done then begin
    let _ = attempt_version cfg ct in `Stop
  end
  else (sleep_ms cfg.poll_interval_ms; `Continue true)

let on_unstable cfg ct issues ~stable_seen =
  process_unstable cfg ct issues;
  if test_exit_now cfg then `Stop
  else (sleep_ms cfg.poll_interval_ms; `Continue stable_seen)

let process_directives cfg ct directives ~stable_seen =
  if List.mem `Rollback directives then begin
    cfg.emit "directive.rollback" (`Assoc []);
    on_rollback cfg ct; `Stop
  end else if List.mem `Pause directives then begin
    cfg.emit "directive.pause" (`Assoc []);
    sleep_ms cfg.poll_interval_ms; `Continue stable_seen
  end else `No_directive

let one_tick cfg ct ~stable_seen =
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
             | `Stable _ -> on_stable cfg ct ~stable_seen)
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
  let rec loop () =
    match one_tick cfg ct ~stable_seen:!stable with
    | `Stop -> ()
    | `Continue s -> stable := s; loop ()
  in
  loop ();
  cfg.emit "watcher.exit" (`Assoc []);
  0
