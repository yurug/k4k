(** [Watcher_pid] — see [.mli]. *)

let pid_path k4k_dir = Filename.concat k4k_dir "watcher.pid"

(* `kill -0 <pid>` returns 0 iff the process exists and we have
   permission to signal it. Use Unix.kill 0 directly. *)
let pid_alive pid =
  if pid <= 0 then false
  else
    try Unix.kill pid 0; true
    with
    | Unix.Unix_error (Unix.ESRCH, _, _) -> false
    | Unix.Unix_error (Unix.EPERM, _, _) -> true
    | _ -> false

let read_pid_file path : int option =
  if not (Sys.file_exists path) then None
  else
    try
      let raw = String.trim (Persist.read_file path) in
      Some (int_of_string raw)
    with _ -> None

let write_pid_file path =
  Persist.atomic_write ~path (string_of_int (Unix.getpid ()))

let acquire ~k4k_dir : (unit, int) result =
  Persist.ensure_dir k4k_dir;
  let p = pid_path k4k_dir in
  match read_pid_file p with
  | Some pid when pid_alive pid && pid <> Unix.getpid () ->
      Error pid
  | Some _ | None ->
      write_pid_file p;
      Ok ()

let release ~k4k_dir =
  let p = pid_path k4k_dir in
  if Sys.file_exists p then
    (try Unix.unlink p with _ -> ())
