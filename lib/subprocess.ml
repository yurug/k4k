(** [Subprocess] — wrapper around [Unix.create_process] with stdout/stderr
    capture and a wall-clock timeout. Forbidden alternative: [Sys.command]
    (per [conventions/code-style.md]). *)

type result = {
  exit_code : int;
  stdout    : string;
  stderr    : string;
  duration_ms : int;
  timed_out : bool;
}

let read_all fd =
  let buf = Buffer.create 1024 in
  let bytes = Bytes.create 4096 in
  let rec loop () =
    match Unix.read fd bytes 0 4096 with
    | 0 -> ()
    | n -> Buffer.add_subbytes buf bytes 0 n; loop ()
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
    | exception Unix.Unix_error (Unix.EAGAIN, _, _) -> ()
  in
  loop ();
  Buffer.contents buf

let close_safe fd = try Unix.close fd with _ -> ()

let elapsed_ms t0 =
  int_of_float ((Unix.gettimeofday () -. t0) *. 1000.0)

let make_pipe () =
  let r, w = Unix.pipe () in
  Unix.set_close_on_exec r;
  r, w

let waitpid_with_timeout ~child_pid ~timeout_s =
  let t0 = Unix.gettimeofday () in
  let deadline = t0 +. float_of_int timeout_s in
  let rec poll () =
    match Unix.waitpid [Unix.WNOHANG] child_pid with
    | 0, _ ->
        if Unix.gettimeofday () >= deadline then `Timeout
        else begin
          (try ignore (Unix.select [] [] [] 0.05) with _ -> ());
          poll ()
        end
    | _, Unix.WEXITED rc -> `Exited rc
    | _, Unix.WSIGNALED s -> `Signaled s
    | _, Unix.WSTOPPED _ -> poll ()
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> poll ()
    | exception Unix.Unix_error (Unix.ECHILD, _, _) -> `Exited 0
  in
  poll ()

let kill_tree pid =
  (try Unix.kill pid Sys.sigterm with _ -> ());
  let t0 = Unix.gettimeofday () in
  let rec wait () =
    if Unix.gettimeofday () -. t0 > 1.0 then
      (try Unix.kill pid Sys.sigkill with _ -> ())
    else
      match Unix.waitpid [Unix.WNOHANG] pid with
      | 0, _ ->
          (try ignore (Unix.select [] [] [] 0.05) with _ -> ());
          wait ()
      | _ -> ()
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
      | exception Unix.Unix_error (Unix.ECHILD, _, _) -> ()
  in
  wait ();
  (try ignore (Unix.waitpid [] pid) with _ -> ())

let spawn_in ~prog ~argv ~env ~cwd ~stdout_w ~stderr_w
             ~stdout_r ~stderr_r =
  let prev_cwd = Unix.getcwd () in
  Unix.chdir cwd;
  let pid =
    try
      Unix.create_process_env prog argv env
        Unix.stdin stdout_w stderr_w
    with e -> close_safe stdout_w; close_safe stderr_w;
              close_safe stdout_r; close_safe stderr_r;
              Unix.chdir prev_cwd; raise e
  in
  Unix.chdir prev_cwd;
  close_safe stdout_w;
  close_safe stderr_w;
  pid

let exit_code_of_outcome = function
  | `Exited rc -> rc
  | `Signaled s -> 128 + s
  | `Timeout -> -1

let run ?(env = Unix.environment ()) ?(cwd = ".") ?(timeout_s = 60)
    ~prog ~args () =
  let stdout_r, stdout_w = make_pipe () in
  let stderr_r, stderr_w = make_pipe () in
  let argv = Array.of_list (prog :: args) in
  let t0 = Unix.gettimeofday () in
  let pid = spawn_in ~prog ~argv ~env ~cwd
              ~stdout_w ~stderr_w ~stdout_r ~stderr_r in
  let outcome = waitpid_with_timeout ~child_pid:pid ~timeout_s in
  let timed_out = (outcome = `Timeout) in
  if timed_out then kill_tree pid;
  let stdout = read_all stdout_r in
  let stderr = read_all stderr_r in
  close_safe stdout_r; close_safe stderr_r;
  { exit_code = exit_code_of_outcome outcome;
    stdout; stderr;
    duration_ms = elapsed_ms t0; timed_out }
