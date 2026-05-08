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

(* Paths that are universally regenerable and never part of the user's
   committed source: [.k4k/] (k4k's own operational state), [_build/]
   (dune's build output, written by the verifier subprocess), and
   [.*.cotype/] (cotype's per-file sidecar created automatically on
   first run, per ADR-010). All appear as untracked on first run
   regardless of the user's [.gitignore], so we filter them from the
   clean-tree check. *)
let starts_with prefix s =
  let lp = String.length prefix and ls = String.length s in
  ls >= lp && String.sub s 0 lp = prefix

let ends_with suffix s =
  let lp = String.length suffix and ls = String.length s in
  ls >= lp && String.sub s (ls - lp) lp = suffix

(* True iff [p] is itself or sits under a cotype sidecar dir
   (i.e. matches [.*.cotype] or [.*.cotype/...]). cotype sidecars are
   per-file, so the basename is dynamic. *)
let is_cotype_path p =
  let head =
    match String.index_opt p '/' with
    | None -> p
    | Some i -> String.sub p 0 i
  in
  String.length head >= 8
  && head.[0] = '.'
  && ends_with ".cotype" head

let is_ignorable_path line =
  let len = String.length line in
  len >= 4 &&
    let p = String.trim (String.sub line 3 (len - 3)) in
    p = ".k4k" || p = ".k4k/" || p = "_build" || p = "_build/" ||
    starts_with ".k4k/" p || starts_with "_build/" p ||
    is_cotype_path p

let is_clean ~cwd : bool * string list =
  let r = run_git ~cwd ["status"; "--porcelain"] in
  let lines =
    String.split_on_char '\n' r.stdout
    |> List.filter (fun s -> s <> "" && not (is_ignorable_path s))
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

(* C1 — NF4 envelope. The patch file used to land in /tmp via
   [Filename.temp_file]; route it under [<cwd>/.k4k/scratch/<id>/]
   instead. The directory and file are created via [Persist] so the
   K4K_TEST_TRACE_WRITES hook captures them. *)
let apply_diff ~cwd ~diff : (unit, string) result =
  let id = Persist.agent_run_id () in
  let scratch_dir = Filename.concat cwd
    (Filename.concat ".k4k" (Filename.concat "scratch" id)) in
  let tmp = Filename.concat scratch_dir "gap.patch" in
  Persist.atomic_write ~path:tmp diff;
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

(* ADR-013 §2 step 5: merge a version branch into the default branch.
   Try fast-forward first; fall back to a no-fast-forward merge with a
   k4k-authored message. *)
let merge ~cwd ~name ~message : (unit, string) result =
  let r = run_git ~cwd ["merge"; "--ff-only"; name] in
  if r.exit_code = 0 then Ok ()
  else
    let r2 = run_git ~cwd
      ["merge"; "--no-ff"; "-m"; message; name] in
    if r2.exit_code = 0 then Ok () else Error (trim r2.stderr)

(* ADR-013 §2 step 5: annotated tag at HEAD. *)
let tag_annotated ~cwd ~name ~message : (unit, string) result =
  let r = run_git ~cwd ["tag"; "-a"; name; "-m"; message] in
  if r.exit_code = 0 then Ok () else Error (trim r.stderr)

let tag_exists ~cwd ~name : bool =
  let r = run_git ~cwd ["rev-parse"; "--verify"; "--quiet";
                        "refs/tags/" ^ name] in
  r.exit_code = 0

let head_sha ~cwd : (string, string) result =
  let r = run_git ~cwd ["rev-parse"; "HEAD"] in
  if r.exit_code = 0 then Ok (trim r.stdout) else Error (trim r.stderr)

(* ADR-013 §2 + Version.current_default_branch: find the default branch
   name. Try [origin/HEAD] first; fall back to any local [main] /
   [master]; otherwise return the current branch. Result is best-effort
   (used as a hint, not a contract). *)
let default_branch ~cwd : string =
  let r = run_git ~cwd
    ["symbolic-ref"; "--short"; "refs/remotes/origin/HEAD"] in
  if r.exit_code = 0 then
    let s = trim r.stdout in
    (* "origin/main" -> "main" *)
    match String.index_opt s '/' with
    | None -> s
    | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  else if branch_exists ~cwd ~name:"main" then "main"
  else if branch_exists ~cwd ~name:"master" then "master"
  else current_branch ~cwd

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
