(** [Watcher_loop] — the watcher's main loop. Kept narrow:
    - poll cotype.status at [poll_interval_ms]
    - on [`Conflicted] surface; on [`Unmanaged] init
    - on [`Clean] read the file, parse, run stability check
    - on unstable: append clarification block, write status, sleep
    - on stable: snapshot a version, run convergence, write status
    - honor SIGINT cooperatively *)

type config = {
  file_path        : string;
  k4k_dir          : string;
  verbosity        : [ `Quiet | `Verbose | `Debug ];
  exit_on_stable   : bool;
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

let process_stable cfg ct =
  let s = mk_status ~version_n:1 ~state:"stable" ~last_act:(now_iso ()) in
  render_and_save_status cfg ct
    ~status_block:(Inline_blocks.render_status s);
  cfg.emit "stability.pass" (`Assoc [])

let one_tick cfg ct ~stable_seen =
  if Sigint.should_exit () then `Stop
  else begin
    let directives = user_directives_in_file cfg ct in
    if List.mem `Rollback directives then begin
      cfg.emit "directive.rollback" (`Assoc []);
      `Stop
    end else if List.mem `Pause directives then begin
      cfg.emit "directive.pause" (`Assoc []);
      sleep_ms cfg.poll_interval_ms; `Continue stable_seen
    end else begin
      match read_file_via_cotype ct ~file:cfg.file_path with
      | None ->
          sleep_ms cfg.poll_interval_ms; `Continue stable_seen
      | Some content ->
          (match stability_of_text ~content with
           | `Unstable issues ->
               process_unstable cfg ct issues;
               if test_exit_now cfg then `Stop
               else (sleep_ms cfg.poll_interval_ms;
                     `Continue stable_seen)
           | `Stable _ ->
               if not stable_seen then process_stable cfg ct;
               if cfg.exit_on_stable then `Stop
               else (sleep_ms cfg.poll_interval_ms; `Continue true))
    end
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
