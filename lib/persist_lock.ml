(** [Persist_lock] — P12 file-locking discipline for writes to
    <file.k4k>. Per kb/spec/config-and-formats.md and
    kb/properties/functional.md#P12, every writer to the user-owned
    interaction file must hold an advisory exclusive lock for the
    duration of the write only — never across an agent or verifier
    call. The lock is released before this function returns. *)

let raise_disk_full path =
  raise (Error.K4k_error (Error.E_disk_full path))

(* Ensure the file exists so we can open it for locking; touch it
   without modifying contents. *)
let touch_file path =
  if not (Sys.file_exists path) then begin
    let fd =
      try
        Unix.openfile path
          [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND ] 0o644
      with Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full path
    in
    Unix.close fd
  end

(* Acquire an exclusive advisory lock on [path]; run [k]; release.
   [Unix.lockf] on a file descriptor with [F_LOCK] blocks until the
   lock is acquired. We open the file read-write so the lock applies
   to writers in the conventional sense; the caller does the actual
   write through whatever channel it prefers (atomic_write, append,
   …). The fd is dedicated to the lock and closed after. *)
let with_exclusive_lock ~path k =
  touch_file path;
  let fd =
    try Unix.openfile path [ Unix.O_RDWR ] 0o644
    with Unix.Unix_error (Unix.ENOENT, _, _) ->
      Unix.openfile path [ Unix.O_RDWR; Unix.O_CREAT ] 0o644
  in
  let acquired = ref false in
  let r =
    try
      Unix.lockf fd Unix.F_LOCK 0;
      acquired := true;
      let v = k () in
      Unix.lockf fd Unix.F_ULOCK 0;
      acquired := false;
      v
    with e ->
      if !acquired then
        (try Unix.lockf fd Unix.F_ULOCK 0 with _ -> ());
      Unix.close fd;
      raise e
  in
  Unix.close fd;
  r

(* Append [text] to <file.k4k> under an exclusive flock. The lock is
   held for the duration of the write only; concurrent appenders
   serialise. NF4: writes to <file.k4k> are inside the envelope. *)
let append_clarification ~path text =
  Persist.trace_write_path path;
  with_exclusive_lock ~path (fun () ->
    let fd =
      try
        Unix.openfile path
          [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND ] 0o644
      with Unix.Unix_error (Unix.ENOSPC, _, _) -> raise_disk_full path
    in
    let buf = Bytes.unsafe_of_string text in
    let len = Bytes.length buf in
    let rec loop off =
      if off >= len then ()
      else
        let n =
          try Unix.write fd buf off (len - off)
          with Unix.Unix_error (Unix.ENOSPC, _, _) ->
            (try Unix.close fd with _ -> ()); raise_disk_full path
        in
        loop (off + n)
    in
    (try loop 0; (try Unix.fsync fd with _ -> ())
     with e -> (try Unix.close fd with _ -> ()); raise e);
    Unix.close fd)
