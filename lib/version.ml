(** [Version] — per-version state machine + git-branch lifecycle. See
    [version.mli]. All git side-effects route through [Git]. *)

type state =
  | Drafting
  | Refining
  | Stable
  | Developing
  | Awaiting_tradeoff
  | Paused_unknown
  | Done
  | Rolled_back

type t = {
  number           : int;
  state            : state;
  baseline_sha     : string;
  branch_name      : string;
  d_hash           : string;
  started_at       : float;
  tier_assignments : (string * [ `A | `B | `C ]) list;
}

let branch_name_of n = Printf.sprintf "k4k/version/%d" n

let tag_name_of n = Printf.sprintf "v%d" n

let state_to_string = function
  | Drafting          -> "drafting"
  | Refining          -> "refining"
  | Stable            -> "stable"
  | Developing        -> "developing"
  | Awaiting_tradeoff -> "awaiting_tradeoff"
  | Paused_unknown    -> "paused_unknown"
  | Done              -> "done"
  | Rolled_back       -> "rolled_back"

let state_of_string = function
  | "drafting"          -> Drafting
  | "refining"          -> Refining
  | "stable"            -> Stable
  | "developing"        -> Developing
  | "awaiting_tradeoff" -> Awaiting_tradeoff
  | "paused_unknown"    -> Paused_unknown
  | "done"              -> Done
  | "rolled_back"       -> Rolled_back
  | s -> raise (Error.K4k_error (Error.E_format
      { line = 0; col = 0;
        reason = Printf.sprintf "version: unknown state %S" s }))

let tier_to_string = function `A -> "A" | `B -> "B" | `C -> "C"

let tier_of_string = function
  | "A" -> `A
  | "B" -> `B
  | "C" -> `C
  | s -> raise (Error.K4k_error (Error.E_format
      { line = 0; col = 0;
        reason = Printf.sprintf "version: unknown tier %S" s }))

let start_new ~cwd ~number ~baseline_sha ~d_hash : (t, string) result =
  let branch = branch_name_of number in
  if Git.branch_exists ~cwd ~name:branch then
    Error (Printf.sprintf
      "branch %s already exists (E_state_corrupt: caller must reconcile)"
      branch)
  else
    match Git.create_branch ~cwd ~name:branch with
    | Error e -> Error e
    | Ok () ->
        Ok { number;
             state = Developing;
             baseline_sha;
             branch_name = branch;
             d_hash;
             started_at = Unix.gettimeofday ();
             tier_assignments = []; }

let commit_accept ~cwd ~property_id:_ ~message : (string, string) result =
  match Git.commit_all ~cwd ~message with
  | Error e -> Error e
  | Ok () -> Git.head_sha ~cwd

let complete ~cwd t ~default_branch ?(delete_branch = true) ()
    : (string, string) result =
  match Git.checkout ~cwd ~name:default_branch with
  | Error e -> Error e
  | Ok () ->
      let merge_msg =
        Printf.sprintf "[k4k] merge version %d" t.number in
      (match Git.merge ~cwd ~name:t.branch_name ~message:merge_msg with
       | Error e -> Error e
       | Ok () ->
           let tag = tag_name_of t.number in
           let tag_msg = Printf.sprintf
             "k4k version %d (D-hash %s)" t.number t.d_hash in
           (match Git.tag_annotated ~cwd ~name:tag ~message:tag_msg with
            | Error e -> Error e
            | Ok () ->
                if delete_branch then
                  let _ = Git.delete_branch ~cwd ~name:t.branch_name in
                  Ok tag
                else Ok tag))

let rollback ~cwd t ~default_branch : (unit, string) result =
  let _ = Git.checkout ~cwd ~name:default_branch in
  if Git.branch_exists ~cwd ~name:t.branch_name then
    Git.delete_branch ~cwd ~name:t.branch_name
  else Ok ()

let current_default_branch ~cwd = Git.default_branch ~cwd

(* --- JSON codec --- *)

let to_yojson (t : t) : Yojson.Safe.t =
  `Assoc [
    "number",       `Int t.number;
    "state",        `String (state_to_string t.state);
    "baseline_sha", `String t.baseline_sha;
    "branch_name",  `String t.branch_name;
    "d_hash",       `String t.d_hash;
    "started_at",   `Float t.started_at;
    "tier_assignments",
      `List (List.map (fun (pid, tier) ->
        `Assoc [ "property_id", `String pid;
                 "tier", `String (tier_to_string tier) ])
        t.tier_assignments);
  ]

let lookup_or_fail k = function
  | `Assoc fs ->
      (try List.assoc k fs
       with Not_found ->
         raise (Error.K4k_error (Error.E_format
           { line = 0; col = 0;
             reason = "version: missing field " ^ k })))
  | _ ->
      raise (Error.K4k_error (Error.E_format
        { line = 0; col = 0;
          reason = "version: expected object" }))

let str_of = function
  | `String s -> s
  | _ -> raise (Error.K4k_error (Error.E_format
      { line = 0; col = 0;
        reason = "version: expected string" }))

let int_of = function
  | `Int i -> i
  | _ -> raise (Error.K4k_error (Error.E_format
      { line = 0; col = 0; reason = "version: expected int" }))

let float_of = function
  | `Float f -> f
  | `Int i -> float_of_int i
  | _ -> raise (Error.K4k_error (Error.E_format
      { line = 0; col = 0; reason = "version: expected number" }))

let of_yojson v : t =
  let g k = lookup_or_fail k v in
  let assigns =
    match g "tier_assignments" with
    | `List xs ->
        List.map (fun x ->
          let pid = str_of (lookup_or_fail "property_id" x) in
          let tier = tier_of_string
            (str_of (lookup_or_fail "tier" x)) in
          (pid, tier)) xs
    | _ -> []
  in
  { number = int_of (g "number");
    state = state_of_string (str_of (g "state"));
    baseline_sha = str_of (g "baseline_sha");
    branch_name = str_of (g "branch_name");
    d_hash = str_of (g "d_hash");
    started_at = float_of (g "started_at");
    tier_assignments = assigns; }
