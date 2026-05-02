type crash_hook = unit -> unit

let no_crash () = ()

(* Per spec/config-and-formats.md: 10 MiB. *)
let max_interaction_file_bytes = 10 * 1024 * 1024

let raise_disk_full path = raise (Error.K4k_error (Error.E_disk_full path))

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
  let parent = Filename.dirname path in
  ensure_dir parent;
  let tmp = path ^ ".tmp" in
  with_out_fd ~path:tmp (fun fd ->
      let buf = Bytes.unsafe_of_string content in
      write_all fd buf;
      try Unix.fsync fd with _ -> ());
  crash_hook ();
  (try Unix.rename tmp path
   with Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full path);
  fsync_dir parent

let append_jsonl_line ~path ~line =
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
