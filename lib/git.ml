(** [Git] — minimal git wrapper used by [Gap_step] for scratch-branch
    discipline (Q3.2). All operations go through [Subprocess.run].

    Pre-conditions enforced here:
    - [is_repo] confirms the directory is a git working tree.
    - [is_clean] confirms the working tree has no uncommitted changes.

    Higher-level workflow (create scratch branch, apply diff, merge or
    discard) lives in [Gap_step]. *)

let run_git ~cwd args =
  Subprocess.run ~prog:"git" ~args ~cwd ~timeout_s:30 ()

let trim s =
  let n = String.length s in
  let rec last i =
    if i < 0 then -1
    else match s.[i] with
      | ' ' | '\t' | '\n' | '\r' -> last (i - 1)
      | _ -> i
  in
  let i = last (n - 1) in
  if i < 0 then "" else String.sub s 0 (i + 1)

let is_repo ~cwd : bool =
  let r = run_git ~cwd ["rev-parse"; "--git-dir"] in
  r.exit_code = 0

let current_branch ~cwd : string =
  let r = run_git ~cwd ["rev-parse"; "--abbrev-ref"; "HEAD"] in
  trim r.stdout

let is_clean ~cwd : bool * string list =
  let r = run_git ~cwd ["status"; "--porcelain"] in
  let lines =
    String.split_on_char '\n' r.stdout
    |> List.filter (fun s -> s <> "")
  in
  (lines = [], lines)

let branch_exists ~cwd ~name : bool =
  let r = run_git ~cwd
    ["rev-parse"; "--verify"; "--quiet"; name] in
  r.exit_code = 0

let create_branch ~cwd ~name : (unit, string) result =
  let r = run_git ~cwd ["checkout"; "-b"; name] in
  if r.exit_code = 0 then Ok ()
  else Error (trim r.stderr)

let checkout ~cwd ~name : (unit, string) result =
  let r = run_git ~cwd ["checkout"; name] in
  if r.exit_code = 0 then Ok () else Error (trim r.stderr)

let delete_branch ~cwd ~name : (unit, string) result =
  let r = run_git ~cwd ["branch"; "-D"; name] in
  if r.exit_code = 0 then Ok () else Error (trim r.stderr)

let apply_diff ~cwd ~diff : (unit, string) result =
  (* Pipe the diff via a temporary file (no clean way to write to git's
     stdin via Subprocess at present). *)
  let tmp = Filename.temp_file "k4k-gap-" ".patch" in
  let oc = open_out tmp in
  output_string oc diff;
  close_out oc;
  let r = run_git ~cwd ["apply"; "--index"; tmp] in
  (try Sys.remove tmp with _ -> ());
  if r.exit_code = 0 then Ok () else Error (trim r.stderr)

let commit_all ~cwd ~message : (unit, string) result =
  let r1 = run_git ~cwd ["add"; "-A"] in
  if r1.exit_code <> 0 then Error (trim r1.stderr)
  else
    let r2 = run_git ~cwd ["commit"; "-m"; message;
                           "--allow-empty"] in
    if r2.exit_code = 0 then Ok () else Error (trim r2.stderr)

let merge_ff_only ~cwd ~name : (unit, string) result =
  let r = run_git ~cwd ["merge"; "--ff-only"; name] in
  if r.exit_code = 0 then Ok () else Error (trim r.stderr)

let init ~cwd : (unit, string) result =
  let r = run_git ~cwd ["init"; "-q"; "-b"; "main"] in
  if r.exit_code = 0 then Ok () else Error (trim r.stderr)

let configure_test_identity ~cwd =
  let _ = run_git ~cwd ["config"; "user.email"; "k4k-test@example.invalid"] in
  let _ = run_git ~cwd ["config"; "user.name"; "k4k-test"] in
  ()

let scratch_branch_name ~property_id =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  let stamp = Printf.sprintf "%04d%02d%02d-%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec in
  let rand = Printf.sprintf "%06x" (Random.bits () land 0xffffff) in
  Printf.sprintf "k4k/gap/%s/%s-%s" property_id stamp rand
