(** [Version_user_edits] — P22 user-edits-during-development queueing.
    See [.mli]. *)

type cfg = {
  cwd       : string;
  emit      : string -> Yojson.Safe.t -> unit;
  file_path : string option;
}

let read_via_cotype ~cotype ~file_path =
  match cotype, file_path with
  | Some ct, Some fp ->
      (try Some (Cotype.read_base ct ~file:fp)
       with _ -> None)
  | _ -> None

let snapshot ?cotype ~file_path () : (string * string) list =
  match read_via_cotype ~cotype ~file_path with
  | None -> []
  | Some content ->
      (try
         let parsed = Parser.parse content in
         Stability.user_section_hashes parsed
       with _ -> [])

let count_drift ~baseline_hashes ~current_hashes : int =
  List.length (List.filter (fun (k, v) ->
    match List.assoc_opt k current_hashes with
    | None -> true
    | Some v' -> v <> v') baseline_hashes)

let render_status n_pending v_number =
  let s : Inline_blocks.status = {
    version_n = v_number;
    state = "developing";
    tier_dist = { tier_a = 0; tier_b = 0; tier_c = 0 };
    pending_user_edits = n_pending;
    last_activity = Inline_blocks.timestamp_now ();
    open_tradeoffs = 0;
  } in
  Inline_blocks.render_status s

let splice_status_block ~cotype ~file_path ~status_block =
  try
    let opened = Cotype.open_ cotype ~file:file_path in
    match opened with
    | Error _ -> ()
    | Ok r ->
        let base = Persist.read_file r.base_path in
        let merged = Status_splice.replace_or_append base status_block in
        let _ = Cotype.save cotype ~file:file_path
                  ~base_sha:r.base_sha ~actor:"agent:k4k"
                  ~bytes:merged in ()
  with _ -> ()

let commit_residue ~cwd ~v_number ~n =
  let clean, _ = Git.is_clean ~cwd in
  if not clean then
    let msg = Printf.sprintf
      "[k4k] queue user edits for v%d (%d section%s)"
      (v_number + 1) n (if n = 1 then "" else "s") in
    let _ = Git.commit_all ~cwd ~message:msg in ()

let check_and_queue ~cfg ~v_number ~baseline ~surfaced ?cotype () : int =
  let current = snapshot ?cotype ~file_path:cfg.file_path () in
  let n = count_drift ~baseline_hashes:baseline ~current_hashes:current in
  if n > 0 && n <> !surfaced then begin
    cfg.emit "user_edits.queued"
      (`Assoc [ "version", `Int v_number;
                "count", `Int n ]);
    let block = render_status n v_number in
    (match cfg.file_path, cotype with
     | Some fp, Some ct ->
         splice_status_block ~cotype:ct ~file_path:fp ~status_block:block
     | _ -> ());
    commit_residue ~cwd:cfg.cwd ~v_number ~n;
    surfaced := n
  end;
  n
