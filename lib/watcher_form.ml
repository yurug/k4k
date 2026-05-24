(** [Watcher_form] — v2 batch 4b: real formalization driver for the
    watcher's development half.

    Replaces the [K4K_TEST_D_PATH] knob: derives the canonical [D]
    from the interaction file's user-owned sections by running the
    two-run formalization protocol ([Stability.semantic_check_with_backend])
    against an injected agent-invoke closure (canned in tests, external
    in production), then persists [.k4k/characterization/desired/]
    + [.k4k/manifest.json] atomically. The cache short-circuit ([P19])
    is honored: when user-section hashes equal those in the previous
    manifest and the cached [D] is on disk, the agent is not called. *)

type emit_fn = string -> Yojson.Safe.t -> unit

type agent_invoke =
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result

let render_prompt parsed =
  let user_sections = Stability.render_user_sections parsed in
  Prompts.render "formalize.md"
    [ "user_sections", user_sections;
      "example_input", "";
      "example_output", "" ]

let mirror_md (d : Characterization.t) =
  Printf.sprintf
    "---\nowner: k4k\ncontent_hash: %s\n---\n# Desired Characterization\n\n\
     Goal: %s\n\nClass: %s\n"
    d.hash d.goal d.cls

let persist_desired ~k4k_dir d =
  let bytes = Canonical_json.to_string
                (Characterization_json.to_yojson d) in
  Persist.write_desired ~k4k_dir ~bytes ~mirror_md:(mirror_md d)

let load_cached ~k4k_dir ~hash =
  match hash with
  | None -> None
  | Some _ ->
      let p = Filename.concat k4k_dir
                "characterization/desired/spec.json" in
      if not (Sys.file_exists p) then None
      else
        try
          let raw = Persist.read_file p in
          let j = Yojson.Safe.from_string raw in
          let c = Characterization_decoder.of_yojson j in
          Some (Canonicalize.canonicalize c)
        with _ -> None

let persist_manifest ~k4k_dir ~file_path ~content ~user_h ~d =
  let mj = Manifest.build
    ~file_path ~file_sha256:(Persist.sha256_hex content)
    ~user_section_hashes:user_h
    ~agent_name:"canned-or-external"
    ~agent_version:"watcher-form"
    ~verifier_name:"external"
    ~verifier_version:""
    ~desired_hash:d.Characterization.hash () in
  Persist.atomic_write
    ~path:(Filename.concat k4k_dir "manifest.json")
    (Yojson.Safe.pretty_to_string ~std:true mj)

(** Invoker wrapper for [Stability.semantic_check_with_backend]. *)
let invoker_of_invoke (f : agent_invoke) : unit Stability.backend_invoker =
  { Stability.bk = ();
    invoke = (fun ~purpose ~prompt ~budget ->
      f ~purpose ~prompt ~budget) }

(** [run ~k4k_dir ~content ~agent_invoke ~emit] returns [Ok d] when
    the two-run formalization succeeds (or hits the cache); [Error reason]
    when the spec semantically diverges or any other recoverable issue
    surfaces. Structural stability is assumed already-checked by the
    caller. *)
let invoke_semantic ~k4k_dir ~prompt ~prev_h ~user_h ~cached inv =
  try
    `Ok (Stability.semantic_check_with_backend
           ~k4k_dir ~prompt ~budget:Budget.default_per_call
           ~prev_hashes:prev_h ~current_hashes:user_h
           ~cached_desired:cached inv)
  with Error.K4k_error e -> `Err (Error.render e)

let on_stable ~k4k_dir ~content ~user_h ~emit d =
  let cov = Coverage.check d in
  if cov <> [] then begin
    emit "formalize.coverage_unstable"
      (`Assoc [ "issue_count", `Int (List.length cov) ]);
    Error "coverage-unstable"
  end else begin
    persist_desired ~k4k_dir d;
    persist_manifest ~k4k_dir ~file_path:"" ~content ~user_h ~d;
    emit "formalize.ok" (`Assoc [ "hash", `String d.Characterization.hash ]);
    Ok d
  end

let dispatch_outcome ~k4k_dir ~content ~user_h ~emit = function
  | `Err reason ->
      emit "formalize.error" (`Assoc [ "reason", `String reason ]);
      Error reason
  | `Ok (Stability.Sem_cached d) ->
      emit "formalize.cached" (`Assoc [ "hash", `String d.hash ]);
      Ok d
  | `Ok (Stability.Sem_stable (d, _runs)) ->
      on_stable ~k4k_dir ~content ~user_h ~emit d
  | `Ok (Stability.Sem_unstable (issues, _)) ->
      emit "formalize.unstable"
        (`Assoc [ "issue_count", `Int (List.length issues) ]);
      Error "formalization-unstable"

let run ~k4k_dir ~content ~agent_invoke ~emit
    : (Characterization.t, string) result =
  let parsed = Parser.parse content in
  Persist.ensure_dir k4k_dir;
  let manifest = Manifest.read_or_init ~k4k_dir in
  let prev_h = Manifest.user_section_hashes manifest in
  let user_h = Stability.user_section_hashes parsed in
  let cached = load_cached ~k4k_dir
                 ~hash:(Manifest.desired_hash manifest) in
  let prompt = render_prompt parsed in
  let inv = invoker_of_invoke agent_invoke in
  dispatch_outcome ~k4k_dir ~content ~user_h ~emit
    (invoke_semantic ~k4k_dir ~prompt ~prev_h ~user_h ~cached inv)
