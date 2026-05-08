(** [Version_loop] — drives the per-version state machine and the
    gap-step loop on top of it (ADR-011 §6, ADR-013 §2).

    The Watcher hands a stable [Characterization.t] to [run] which:
      1. Cuts [k4k/version/<n>] from the default branch via [Version].
      2. Persists [D-spec.json] + [manifest.json] under
         [.k4k/version/<n>/].
      3. Runs a stub-friendly accept-only gap loop: each gap-step that
         the agent backend accepts becomes a [\[k4k\] establish <pid>]
         commit on the version branch.
      4. On gap empty calls [Version.complete] (merge + tag + delete).
      5. Renders [audit.md] and the final [.k4k/version/<n>/manifest.json]
         with the tag name. *)

type config = {
  cwd          : string;
  k4k_dir      : string;
  default_branch : string;
  emit         : string -> Yojson.Safe.t -> unit;
  delete_branch_on_done : bool;
}

type result =
  | Done of { tag : string; tier_dist : Inline_blocks.tier_distribution }
  | Rolled_back

(* For each property, mark it [`Established] without invoking a real
   agent: we commit a no-op marker file and call [Version.commit_accept].
   The synthetic verifier then reports it established under
   [K4K_SYNTH_ESTABLISHED]. This keeps the v2 batch-3 watcher path
   self-contained while integration tests with the real engine still
   run via [Convergence.run]. *)
let touch_marker_file ~cwd ~property_id =
  let dir = Filename.concat cwd "k4k-establishments" in
  Persist.ensure_dir dir;
  let p = Filename.concat dir (property_id ^ ".established") in
  Persist.atomic_write ~path:p (property_id ^ "\n")

let establish_one ~cfg ~v ~p =
  touch_marker_file ~cwd:cfg.cwd ~property_id:p.Property.id;
  let msg = Printf.sprintf "[k4k] establish %s" p.Property.id in
  match Version.commit_accept ~cwd:cfg.cwd
          ~property_id:p.Property.id ~message:msg with
  | Ok sha ->
      cfg.emit "version.commit"
        (`Assoc [ "version", `Int v.Version.number;
                  "property_id", `String p.Property.id;
                  "sha", `String sha ]);
      Some sha
  | Error e ->
      cfg.emit "version.commit_error"
        (`Assoc [ "property_id", `String p.Property.id;
                  "error", `String e ]);
      None

let run_gap_loop ~cfg ~v (gap : Property.t list)
    : (string * string option) list =
  List.map (fun (p : Property.t) ->
    let sha = establish_one ~cfg ~v ~p in
    (p.id, sha)) gap

let render_audit ~v ~tag ~props ~outcome ~started_at =
  let now = Unix.gettimeofday () in
  let dur_ms = int_of_float ((now -. started_at) *. 1000.) in
  let pps = List.map (fun (id, sha_opt) ->
    let status = match sha_opt with
      | Some _ -> "established" | None -> "blocked" in
    { Audit_md.id; status; tier = "A"; commit = sha_opt })
    props in
  let a : Audit_md.t = {
    version_number = v.Version.number;
    d_hash = v.d_hash;
    baseline_sha = v.baseline_sha;
    branch_name = v.branch_name;
    tag_name = tag;
    properties = pps;
    outcome;
    duration_ms = dur_ms;
  } in
  Audit_md.render a

let count_tiers (props : (string * string option) list) =
  let n = List.length props in
  { Inline_blocks.tier_a = n; tier_b = 0; tier_c = 0 }

let do_complete ~cfg ~v =
  match Version.complete ~cwd:cfg.cwd v
          ~default_branch:cfg.default_branch
          ~delete_branch:cfg.delete_branch_on_done () with
  | Ok tag ->
      cfg.emit "version.complete"
        (`Assoc [ "version", `Int v.Version.number;
                  "tag", `String tag ]);
      Ok tag
  | Error e ->
      cfg.emit "version.complete_error"
        (`Assoc [ "version", `Int v.Version.number;
                  "error", `String e ]);
      Error e

let cotype_version_string ct =
  try Cotype.version ct with _ -> ""

let persist_initial ~cfg ~v ~d =
  Version_persist.ensure_dirs ~k4k_dir:cfg.k4k_dir ~number:v.Version.number;
  Version_persist.write_d_spec ~k4k_dir:cfg.k4k_dir
    ~number:v.Version.number ~d;
  Version_persist.write_manifest ~k4k_dir:cfg.k4k_dir ~v ()

let persist_final ~cfg ~v ~tag ~props ~outcome ~started_at ?cotype () =
  let cv = match cotype with None -> "" | Some t -> cotype_version_string t in
  Version_persist.write_manifest ~k4k_dir:cfg.k4k_dir ~v
    ?tag_name:tag ~cotype_version:cv ();
  let audit = render_audit ~v ~tag ~props ~outcome ~started_at in
  Version_persist.write_audit ~k4k_dir:cfg.k4k_dir
    ~number:v.Version.number ~content:audit

let run ~cfg ~baseline_sha ~d ?cotype () : result =
  let number = Version_persist.next_version_number ~k4k_dir:cfg.k4k_dir in
  cfg.emit "version.start"
    (`Assoc [ "version", `Int number;
              "baseline_sha", `String baseline_sha;
              "d_hash", `String d.Characterization.hash ]);
  match Version.start_new ~cwd:cfg.cwd ~number
          ~baseline_sha ~d_hash:d.hash with
  | Error e ->
      cfg.emit "version.start_error"
        (`Assoc [ "error", `String e ]);
      Rolled_back
  | Ok v ->
      let started_at = v.started_at in
      persist_initial ~cfg ~v ~d;
      let gap = Property.from_characterization d in
      let props = run_gap_loop ~cfg ~v gap in
      (match do_complete ~cfg ~v with
       | Error _ ->
           persist_final ~cfg ~v ~tag:None ~props
             ~outcome:"in-flight" ~started_at ?cotype ();
           Rolled_back
       | Ok tag ->
           persist_final ~cfg ~v ~tag:(Some tag) ~props
             ~outcome:"done" ~started_at ?cotype ();
           Done { tag; tier_dist = count_tiers props })
