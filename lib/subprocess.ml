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

(* Drain a pipe with a wall-clock deadline. Used after [kill_tree] so a
   non-cooperating child that holds the write end (e.g. a grandchild
   orphaned by killing only the shell wrapper) can't wedge the parent
   in a blocking [Unix.read]. The process-group kill in [spawn_in] is
   the primary defense; this is the safety net for cases where the
   grandchild escaped its group (rare, e.g. CGroup interaction). *)
let read_with_deadline ?(deadline_s = 0.5) fd =
  let buf = Buffer.create 1024 in
  let bytes = Bytes.create 4096 in
  let t_end = Unix.gettimeofday () +. deadline_s in
  let rec loop () =
    let remaining = t_end -. Unix.gettimeofday () in
    if remaining <= 0.0 then ()
    else
      match Unix.select [fd] [] [] (min 0.1 remaining) with
      | [], _, _ -> loop ()
      | _ ->
          (match Unix.read fd bytes 0 4096 with
           | 0 -> ()
           | n -> Buffer.add_subbytes buf bytes 0 n; loop ()
           | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
           | exception Unix.Unix_error (Unix.EAGAIN, _, _) -> loop ())
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
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

(* Kill the child AND every process in its process group. The group is
   set up by [spawn_in] via [setpgid pid pid]; signalling the negative
   pgid via [Unix.kill (-pid)] hits the whole subtree (POSIX). Without
   this, a backend that wraps the work in a shell (e.g. [#!/bin/sh\nclaude
   ...]) would orphan its grandchildren when only the shell is killed
   — the grandchildren keep the stdout/stderr pipes open and the
   parent's [read_*] wedges indefinitely. *)
let kill_group pid sig_ =
  (try Unix.kill (- pid) sig_ with _ -> ());
  (try Unix.kill pid sig_ with _ -> ())

let kill_tree pid =
  kill_group pid Sys.sigterm;
  let t0 = Unix.gettimeofday () in
  let rec wait () =
    if Unix.gettimeofday () -. t0 > 1.0 then
      kill_group pid Sys.sigkill
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

(* Read [errno] (one int, little-endian) that the child wrote to the
   exec-status pipe on exec failure. Returns [None] if the read sees
   EOF (= exec succeeded; close-on-exec dropped the write end). *)
let read_exec_errno fd =
  let buf = Bytes.create 4 in
  let rec loop off =
    if off >= 4 then Some (
      Bytes.get_uint8 buf 0
      lor (Bytes.get_uint8 buf 1 lsl 8)
      lor (Bytes.get_uint8 buf 2 lsl 16)
      lor (Bytes.get_uint8 buf 3 lsl 24))
    else
      match Unix.read fd buf off (4 - off) with
      | 0 -> if off = 0 then None
             else Some 0 (* short read: treat as exec ok *)
      | n -> loop (off + n)
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop off
  in
  loop 0

(* Manual fork + setsid + exec, with an errno-pipe so the parent can
   surface ENOENT etc. the same way [Unix.create_process_env] does.
   We need our own fork loop (vs. [create_process_env]) because we
   call [setsid] in the child between fork and exec — that lands the
   backend (and any grandchildren it spawns) in a fresh process group
   so [kill_tree] can wipe out the whole subtree. OCaml stdlib's
   [Unix] doesn't bind [setpgid], so [setsid] is the portable way to
   get the same outcome. *)
let spawn_in ~prog ~argv ~env ~cwd ~stdin_fd ~stdout_w ~stderr_w
             ~stdout_r ~stderr_r =
  let close_parent_ends () =
    close_safe stdout_w; close_safe stderr_w;
    close_safe stdout_r; close_safe stderr_r
  in
  let exec_r, exec_w = Unix.pipe () in
  Unix.set_close_on_exec exec_w;
  match Unix.fork () with
  | exception e ->
      close_safe exec_r; close_safe exec_w;
      close_parent_ends (); raise e
  | 0 ->
      (* CHILD. Do NOT raise OCaml exceptions or run at_exit handlers
         here — that would pollute the parent's view of the heap and
         flush buffers into our shared stdio. On any error, [_exit]. *)
      close_safe exec_r;
      let report_exec_failure code =
        let b = Bytes.create 4 in
        Bytes.set_uint8 b 0 (code land 0xff);
        Bytes.set_uint8 b 1 ((code lsr 8) land 0xff);
        Bytes.set_uint8 b 2 ((code lsr 16) land 0xff);
        Bytes.set_uint8 b 3 ((code lsr 24) land 0xff);
        (try ignore (Unix.write exec_w b 0 4) with _ -> ());
        exit 127
      in
      (try
         let _ = Unix.setsid () in
         if not (chdir_safe cwd) then report_exec_failure 2 (* ENOENT *);
         if stdin_fd <> Unix.stdin then begin
           Unix.dup2 stdin_fd Unix.stdin;
           close_safe stdin_fd
         end;
         Unix.dup2 stdout_w Unix.stdout;
         Unix.dup2 stderr_w Unix.stderr;
         close_safe stdout_w; close_safe stderr_w;
         close_safe stdout_r; close_safe stderr_r;
         Unix.execvpe prog argv env
       with
       | Unix.Unix_error (Unix.ENOENT, _, _) -> report_exec_failure 2
       | Unix.Unix_error (Unix.EACCES, _, _) -> report_exec_failure 13
       | _ -> report_exec_failure 0)
  | pid ->
      close_safe exec_w;
      match read_exec_errno exec_r with
      | None ->
          (* Exec succeeded. *)
          close_safe exec_r;
          close_safe stdout_w;
          close_safe stderr_w;
          pid
      | Some code ->
          (* Exec failed. Reap the child and raise the errno the way
             [Unix.create_process_env] would. *)
          close_safe exec_r;
          (try ignore (Unix.waitpid [] pid) with _ -> ());
          close_parent_ends ();
          let err = match code with
            | 2 -> Unix.ENOENT
            | 13 -> Unix.EACCES
            | _ -> Unix.EUNKNOWNERR code
          in
          raise (Unix.Unix_error (err, "create_process", prog))

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
  let was_killed = timed_out || outcome = `Interrupted in
  if was_killed then kill_tree pid;
  let read fd = if was_killed then read_with_deadline fd else read_all fd in
  let stdout = read stdout_r in
  let stderr = read stderr_r in
  close_safe stdout_r; close_safe stderr_r;
  { exit_code = exit_code_of_outcome outcome;
    stdout; stderr;
    duration_ms = elapsed_ms t0; timed_out }
