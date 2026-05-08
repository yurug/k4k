(** [Watcher_prune] — file-pruning rules per ADR-011 §7.

    Runs on every stable-spec tick; idempotent.

    1. Clarification archival: each `## k4k:clarification:<ts>` section
       in the file is moved to
       [.k4k/clarifications/<ts>.md] (or
       [.k4k/version/<n>/clarifications/<ts>.md] when an in-flight
       version exists), and replaced inline with an HTML-comment
       breadcrumb.
    2. `## k4k:welcome` auto-delete: deleted iff (a) no
       `## k4k:version:<n>` block exists in the file (i.e. no version
       has stabilized yet), AND (b) at least one resolved-clarification
       breadcrumb is present (i.e. at least one round has resolved).

    All file mutations flow through [Cotype.save] (P1, P12). *)

let read_via_cotype ct ~file_path =
  try Some (Cotype.read_base ct ~file:file_path)
  with _ -> None

let save_via_cotype ct ~file_path ~bytes =
  try
    let opened = Cotype.open_ ct ~file:file_path in
    match opened with
    | Error _ -> false
    | Ok r ->
        (match Cotype.save ct ~file:file_path
                 ~base_sha:r.base_sha ~actor:"agent:k4k"
                 ~bytes with
         | Ok _ -> true
         | Error _ -> false)
  with _ -> false

let archive_dir_for ~k4k_dir =
  match (try Some (Version_persist.next_version_number ~k4k_dir - 1)
         with _ -> None) with
  | None | Some 0 ->
      Filename.concat k4k_dir "clarifications"
  | Some n ->
      Version_persist.clarifications_dir ~k4k_dir ~number:n

let archive_clarification ~k4k_dir ~ts ~bytes =
  let dir = archive_dir_for ~k4k_dir in
  Persist.ensure_dir dir;
  let p = Filename.concat dir (ts ^ ".md") in
  Persist.atomic_write ~path:p bytes

(* Replace each `## k4k:clarification:<ts>` block with a breadcrumb,
   archiving the original. Returns the new file bytes (or [None] when
   nothing changed). *)
let prune_clarifications_in ~k4k_dir content =
  let rec loop bytes archived =
    match Inline_blocks_sections.find_clarification_block bytes with
    | None -> if archived = 0 then None else Some bytes
    | Some (ts, start, stop) ->
        let block = String.sub bytes start (stop - start) in
        archive_clarification ~k4k_dir ~ts ~bytes:block;
        let bc = Inline_blocks_sections.breadcrumb_for "clarification" ts
                 ^ "\n" in
        let new_bytes =
          String.sub bytes 0 start ^ bc
          ^ String.sub bytes stop (String.length bytes - stop)
        in
        loop new_bytes (archived + 1)
  in
  loop content 0

let has_version_block content =
  let needle = "## k4k:version:" in
  let n = String.length content and ln = String.length needle in
  let rec scan i =
    if i + ln > n then false
    else if (i = 0 || content.[i - 1] = '\n')
            && String.sub content i ln = needle then true
    else scan (i + 1)
  in
  scan 0

(* Apply the welcome auto-delete rule on the in-memory bytes. *)
let maybe_delete_welcome content =
  if Inline_blocks_sections.has_welcome_section content
     && not (has_version_block content)
     && Inline_blocks_sections.has_resolved_clarification_breadcrumb content
  then Some (Inline_blocks_sections.delete_section_named content
               ~name:"k4k:welcome")
  else None

(** [run ~ct ~file_path ~k4k_dir ~emit] — apply both pruning rules.
    Idempotent. Side effect: at most one cotype save (combining both
    edits if applicable). *)
let run ~ct ~file_path ~k4k_dir ~emit : unit =
  match read_via_cotype ct ~file_path with
  | None -> ()
  | Some content ->
      let after_clar, archived_count =
        match prune_clarifications_in ~k4k_dir content with
        | None -> content, 0
        | Some b ->
            let count =
              let c = ref 0 in
              let needle = "<!-- k4k:clarification " in
              let n = String.length b and ln = String.length needle in
              let rec scan i =
                if i + ln > n then ()
                else if String.sub b i ln = needle then begin
                  incr c; scan (i + ln)
                end else scan (i + 1)
              in
              scan 0; !c
            in
            b, count
      in
      let final_bytes = match maybe_delete_welcome after_clar with
        | None -> after_clar
        | Some b ->
            emit "welcome.deleted" (`Assoc []);
            b
      in
      if final_bytes <> content then begin
        let _ = save_via_cotype ct ~file_path ~bytes:final_bytes in
        if archived_count > 0 then
          emit "clarifications.archived"
            (`Assoc [ "count", `Int archived_count ])
      end
