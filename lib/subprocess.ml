(** [Subprocess] — wrapper around [Unix.create_process] with stdout/stderr
    capture and a wall-clock timeout. Replaces the forbidden Stdlib
    'system' helper (per [conventions/code-style.md]). *)

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
        if Sigint.should_exit () then `Interrupted
        else if Unix.gettimeofday () >= deadline then `Timeout
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

let chdir_safe path =
  try Unix.chdir path; true
  with Unix.Unix_error _ -> false

let spawn_in ~prog ~argv ~env ~cwd ~stdin_fd ~stdout_w ~stderr_w
             ~stdout_r ~stderr_r =
  let prev_cwd = try Unix.getcwd () with _ -> "/" in
  if not (chdir_safe cwd) then begin
    close_safe stdout_w; close_safe stderr_w;
    close_safe stdout_r; close_safe stderr_r;
    raise (Unix.Unix_error (Unix.ENOENT, "chdir", cwd))
  end;
  let pid =
    try
      Unix.create_process_env prog argv env
        stdin_fd stdout_w stderr_w
    with e -> close_safe stdout_w; close_safe stderr_w;
              close_safe stdout_r; close_safe stderr_r;
              let _ = chdir_safe prev_cwd in raise e
  in
  let _ = chdir_safe prev_cwd in
  close_safe stdout_w;
  close_safe stderr_w;
  pid

(* Make an inheritable read-end pipe for the child's stdin and a
   non-inheritable write-end the parent uses to feed [payload]. *)
let make_stdin_pipe () =
  let r, w = Unix.pipe () in
  Unix.set_close_on_exec w;
  r, w

(* Drain [payload] into write fd [w] in chunks; the child reads from
   the corresponding read end. We close [w] when done. *)
let pump_stdin w payload =
  let buf = Bytes.unsafe_of_string payload in
  let len = Bytes.length buf in
  let rec loop off =
    if off >= len then ()
    else
      match Unix.write w buf off (len - off) with
      | n -> loop (off + n)
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop off
      | exception Unix.Unix_error (Unix.EPIPE, _, _) -> ()
  in
  (try loop 0 with _ -> ());
  close_safe w

let exit_code_of_outcome = function
  | `Exited rc -> rc
  | `Signaled s -> 128 + s
  | `Timeout -> -1
  | `Interrupted -> 130

let run ?(env = Unix.environment ()) ?(cwd = ".") ?(timeout_s = 60)
    ?stdin ~prog ~args () =
  let stdout_r, stdout_w = make_pipe () in
  let stderr_r, stderr_w = make_pipe () in
  let stdin_r, stdin_w_opt = match stdin with
    | None -> Unix.stdin, None
    | Some _ -> let r, w = make_stdin_pipe () in r, Some w
  in
  let argv = Array.of_list (prog :: args) in
  let t0 = Unix.gettimeofday () in
  let pid = spawn_in ~prog ~argv ~env ~cwd ~stdin_fd:stdin_r
              ~stdout_w ~stderr_w ~stdout_r ~stderr_r in
  (* If we built our own stdin pipe, close the read-end in the parent
     so the child sees EOF once we've written everything; then pump
     the payload into the write-end. The default [Unix.stdin] case
     intentionally does not close anything. *)
  (match stdin_w_opt with
   | None -> ()
   | Some w ->
       close_safe stdin_r;
       pump_stdin w (match stdin with Some s -> s | None -> ""));
  let outcome = waitpid_with_timeout ~child_pid:pid ~timeout_s in
  let timed_out = (outcome = `Timeout) in
  if timed_out || outcome = `Interrupted then kill_tree pid;
  let stdout = read_all stdout_r in
  let stderr = read_all stderr_r in
  close_safe stdout_r; close_safe stderr_r;
  { exit_code = exit_code_of_outcome outcome;
    stdout; stderr;
    duration_ms = elapsed_ms t0; timed_out }
