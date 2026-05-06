type crash_hook = unit -> unit

let no_crash () = ()

(* Per spec/config-and-formats.md: 10 MiB. *)
let max_interaction_file_bytes = 10 * 1024 * 1024

let raise_disk_full path = raise (Error.K4k_error (Error.E_disk_full path))

(* Fault-injection hook for T5 (NF3). Activates only when the env var
   K4K_FAULT_INJECT_ENOSPC=<substring> is set; the next [atomic_write]
   whose path contains the substring fails with ENOSPC after the tmp
   file is created (before rename). The tmp file is deleted (rollback).
   Production runs leave this env unset; the production code path is
   identical except for the env lookup. *)
let fault_inject_should_fail path =
  match Sys.getenv_opt "K4K_FAULT_INJECT_ENOSPC" with
  | None | Some "" -> false
  | Some pat -> Astring.String.is_infix ~affix:pat path

(* Test-only NF4 trace hook. When K4K_TEST_TRACE_WRITES=<file> is set,
   every [atomic_write] and [append_jsonl_line] call appends its target
   path to the trace file (one path per line). Production runs leave
   this env unset; the env lookup is the only added cost. Used by the
   NF4_state_confinement_envelope test to verify the path whitelist. *)
let trace_write_path path =
  match Sys.getenv_opt "K4K_TEST_TRACE_WRITES" with
  | None | Some "" -> ()
  | Some trace_file ->
      (* Avoid recursion if [path] equals [trace_file]. *)
      if path = trace_file then ()
      else
        try
          let fd = Unix.openfile trace_file
            [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND ] 0o644 in
          let line = path ^ "\n" in
          let buf = Bytes.unsafe_of_string line in
          let _ = Unix.write fd buf 0 (Bytes.length buf) in
          Unix.close fd
        with Unix.Unix_error _ -> ()

let rec ensure_dir path =
  if path = "" || path = "." || path = "/" then ()
  else if Sys.file_exists path && Sys.is_directory path then ()
  else begin
    let parent = Filename.dirname path in
    if parent <> path then ensure_dir parent;
    try Unix.mkdir path 0o755
    with
    | Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    | Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full path
  end

let fsync_dir dir =
  try
    let fd = Unix.openfile dir [ Unix.O_RDONLY ] 0 in
    (try Unix.fsync fd with _ -> ());
    Unix.close fd
  with Unix.Unix_error _ -> ()

let with_out_fd ~path f =
  let fd =
    try
      Unix.openfile path
        [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644
    with
    | Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full path
  in
  let r =
    try f fd
    with e -> (try Unix.close fd with _ -> ()); raise e
  in
  Unix.close fd;
  r

let write_all fd buf =
  let len = Bytes.length buf in
  let rec loop off =
    if off >= len then ()
    else
      let n =
        try Unix.write fd buf off (len - off)
        with Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full "<write>"
      in
      loop (off + n)
  in
  loop 0

let atomic_write ?(crash_hook = no_crash) ~path content =
  trace_write_path path;
  let parent = Filename.dirname path in
  ensure_dir parent;
  let tmp = path ^ ".tmp" in
  with_out_fd ~path:tmp (fun fd ->
      let buf = Bytes.unsafe_of_string content in
      write_all fd buf;
      try Unix.fsync fd with _ -> ());
  crash_hook ();
  if fault_inject_should_fail path then begin
    (try Unix.unlink tmp with Unix.Unix_error _ -> ());
    raise_disk_full path
  end;
  (try Unix.rename tmp path
   with Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full path);
  fsync_dir parent

let append_jsonl_line ~path ~line =
  trace_write_path path;
  let parent = Filename.dirname path in
  ensure_dir parent;
  let fd =
    try
      Unix.openfile path
        [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND ] 0o644
    with Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full path
  in
  let buf = Bytes.unsafe_of_string (line ^ "\n") in
  (try write_all fd buf
   with e -> (try Unix.close fd with _ -> ()); raise e);
  Unix.close fd

let file_size path =
  try (Unix.stat path).Unix.st_size
  with Unix.Unix_error (Unix.ENOENT, _, _) ->
    raise (Error.K4k_error (Error.E_file_not_found path))

let read_file path =
  let size = file_size path in
  if size > max_interaction_file_bytes then
    raise (Error.K4k_error (Error.E_file_too_large size))
  else
    let ic = open_in_bin path in
    let buf = Bytes.create size in
    really_input ic buf 0 size;
    close_in ic;
    Bytes.unsafe_to_string buf

let sha256_hex bytes =
  Digestif.SHA256.(to_hex (digest_string bytes))

(* --- step-2 additions --- *)

let agent_run_id ?(now=Unix.gettimeofday) ?(rand=fun () -> Random.bits ()) () =
  let t = now () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d%02d%02d-%02d%02d%02d-%06x"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec
    (rand () land 0xffffff)

let write_desired ~k4k_dir ~bytes ~mirror_md =
  let dir = Filename.concat k4k_dir "characterization/desired" in
  ensure_dir dir;
  atomic_write ~path:(Filename.concat dir "spec.json") bytes;
  atomic_write ~path:(Filename.concat dir "spec.md") mirror_md

let write_agent_run ~k4k_dir ~run_id ~prompt ~response ~verdict =
  let dir = Filename.concat k4k_dir
    (Filename.concat "agent-runs" run_id) in
  ensure_dir dir;
  atomic_write ~path:(Filename.concat dir "prompt.md") prompt;
  atomic_write ~path:(Filename.concat dir "response.md") response;
  atomic_write ~path:(Filename.concat dir "verdict.json") verdict

let write_divergence_report ~k4k_dir ~run_id ~report =
  let dir = Filename.concat k4k_dir
    (Filename.concat "agent-runs" run_id) in
  ensure_dir dir;
  atomic_write ~path:(Filename.concat dir "divergence.json") report

(* --- step-3 additions --- *)

let gap_path k4k_dir =
  Filename.concat k4k_dir "gap/properties.json"

let write_gap ~k4k_dir ~bytes =
  let dir = Filename.concat k4k_dir "gap" in
  ensure_dir dir;
  atomic_write ~path:(Filename.concat dir "properties.json") bytes

let read_gap ~k4k_dir =
  let p = gap_path k4k_dir in
  if Sys.file_exists p then
    Some (read_file p)
  else None

let write_verifier_run ~k4k_dir ~run_id ~stdout ~stderr ~result =
  let dir = Filename.concat k4k_dir
    (Filename.concat "verifier-runs" run_id) in
  ensure_dir dir;
  atomic_write ~path:(Filename.concat dir "stdout.log") stdout;
  atomic_write ~path:(Filename.concat dir "stderr.log") stderr;
  atomic_write ~path:(Filename.concat dir "result.json") result

(* --- ADR-010: clarification append via cotype --- *)

let timestamp_of_now () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02d-%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

(* Splice: parse [base_bytes] by H2 headings; preserve every section
   that doesn't start with `## k4k:clarification:` byte-for-byte, then
   append a fresh `## k4k:clarification:<ts>` block with [questions]. *)
let render_clarification_section ~timestamp ~questions =
  let buf = Buffer.create 256 in
  Buffer.add_string buf "## k4k:clarification:";
  Buffer.add_string buf timestamp;
  Buffer.add_char buf '\n';
  List.iter (fun q ->
    Buffer.add_string buf "- "; Buffer.add_string buf q;
    Buffer.add_char buf '\n') questions;
  Buffer.contents buf

let splice_clarification ~base_bytes ~timestamp ~questions =
  let block = render_clarification_section ~timestamp ~questions in
  let n = String.length base_bytes in
  let needs_nl =
    n > 0 && base_bytes.[n - 1] <> '\n'
  in
  if needs_nl then base_bytes ^ "\n" ^ block
  else base_bytes ^ block

(* Cotype-injection seam used by [append_clarification_via] and by
   tests that want the in-memory stub. Signatures are written against
   a saturated record so any concrete cotype implementation can be
   adapted with a thin shim. *)

type cotype_open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

type cotype_save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

let raise_state_corrupt_conflict ~conflict_path =
  raise (Error.K4k_error
    (Error.E_state_corrupt
       (Printf.sprintf
          "interaction file conflict: cotype reported overlapping edits; \
           see %s; resolve diff3 markers in your editor and run \
           `cotype resolve <file>` before re-running k4k"
          conflict_path)))

let raise_cotype_error msg =
  raise (Error.K4k_error
    (Error.E_state_corrupt (Printf.sprintf "cotype error: %s" msg)))

let append_clarification_via
    ~ensure_init ~open_ ~save ~path ~questions =
  (match ensure_init ~file:path with
   | Ok () -> ()
   | Error msg -> raise_cotype_error msg);
  let opened : cotype_open_result =
    match open_ ~file:path with
    | Ok r -> r
    | Error msg -> raise_cotype_error msg
  in
  let base_bytes = read_file opened.base_path in
  let proposed = splice_clarification
    ~base_bytes ~timestamp:(timestamp_of_now ()) ~questions in
  match save ~file:path ~base_sha:opened.base_sha
          ~actor:"agent:k4k" ~bytes:proposed with
  | Ok (Direct _ | Merged _ | Noop) -> ()
  | Ok (Conflict { conflict_path }) ->
      raise_state_corrupt_conflict ~conflict_path
  | Error msg -> raise_cotype_error msg

(* Production helper bound to [Cotype]. Lives here so callers don't
   need to import Cotype themselves. *)
let append_clarification ~cotype ~path ~questions =
  let adapt_open r : cotype_open_result =
    let r : Cotype.open_result = r in
    { base_sha = r.base_sha; base_path = r.base_path;
      conflicted = r.conflicted }
  in
  let adapt_save_outcome = function
    | Cotype.Direct s -> Direct s
    | Cotype.Merged s -> Merged s
    | Cotype.Noop -> Noop
    | Cotype.Conflict { conflict_path } -> Conflict { conflict_path }
  in
  append_clarification_via
    ~ensure_init:(fun ~file -> Cotype.ensure_init cotype ~file)
    ~open_:(fun ~file ->
      Result.map adapt_open (Cotype.open_ cotype ~file))
    ~save:(fun ~file ~base_sha ~actor ~bytes ->
      Result.map adapt_save_outcome
        (Cotype.save cotype ~file ~base_sha ~actor ~bytes))
    ~path ~questions
