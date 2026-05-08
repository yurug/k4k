(** [Version_finalize] — version-completion + audit rendering helpers
    extracted from [Version_loop] to keep both files under the
    200-line cap.

    Owns the path that takes a list of per-property outcomes and:
    1. tries [Version.complete] (merge + tag) when all properties are
       established;
    2. writes the final [manifest.json] (with optional tag);
    3. renders + writes [audit.md].

    Pure side-effects routed through [Version_persist] + [Audit_md];
    git side-effects via [Version.complete]. *)

type prop_outcome = {
  id          : string;
  status      : string;     (* "established" | "blocked" | "deferred" *)
  commit_sha  : string option;
}

type emit_fn = string -> Yojson.Safe.t -> unit

let render_audit ~v ~tag ~outcomes ~outcome ~started_at =
  let now = Unix.gettimeofday () in
  let dur_ms = int_of_float ((now -. started_at) *. 1000.) in
  let pps = List.rev_map (fun (po : prop_outcome) ->
    { Audit_md.id = po.id; status = po.status; tier = "A";
      commit = po.commit_sha }) outcomes in
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

let count_tiers (outcomes : prop_outcome list) =
  let n = List.length outcomes in
  { Inline_blocks.tier_a = n; tier_b = 0; tier_c = 0 }

let do_complete ~cwd ~default_branch ~delete_branch ~emit v =
  match Version.complete ~cwd v
          ~default_branch ~delete_branch () with
  | Ok tag ->
      emit "version.complete"
        (`Assoc [ "version", `Int v.Version.number;
                  "tag", `String tag ]);
      Ok tag
  | Error e ->
      emit "version.complete_error"
        (`Assoc [ "version", `Int v.Version.number;
                  "error", `String e ]);
      Error e

let cotype_version_string ct =
  try Cotype.version ct with _ -> ""

let persist_final ~k4k_dir ~v ~tag ~outcomes ~outcome ~started_at ?cotype () =
  let cv = match cotype with
    | None -> ""
    | Some t -> cotype_version_string t in
  Version_persist.write_manifest ~k4k_dir ~v
    ?tag_name:tag ~cotype_version:cv ();
  let audit = render_audit ~v ~tag ~outcomes ~outcome ~started_at in
  Version_persist.write_audit ~k4k_dir
    ~number:v.Version.number ~content:audit

let all_established outcomes =
  List.for_all (fun (po : prop_outcome) ->
    po.status = "established") outcomes

type result =
  | Done of { tag : string; tier_dist : Inline_blocks.tier_distribution }
  | Rolled_back

let finalize ~cwd ~k4k_dir ~default_branch ~delete_branch ~emit
    ~v ~outcomes ~started_at ?cotype () : result =
  if not (all_established outcomes) then begin
    persist_final ~k4k_dir ~v ~tag:None ~outcomes
      ~outcome:"in-flight" ~started_at ?cotype ();
    Rolled_back
  end else
    match do_complete ~cwd ~default_branch ~delete_branch ~emit v with
    | Error _ ->
        persist_final ~k4k_dir ~v ~tag:None ~outcomes
          ~outcome:"in-flight" ~started_at ?cotype ();
        Rolled_back
    | Ok tag ->
        persist_final ~k4k_dir ~v ~tag:(Some tag) ~outcomes
          ~outcome:"done" ~started_at ?cotype ();
        Done { tag; tier_dist = count_tiers outcomes }
