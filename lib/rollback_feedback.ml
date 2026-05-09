(** [Rollback_feedback] — see [.mli]. *)

type emit_fn = string -> Yojson.Safe.t -> unit

let streak_threshold = 3

let post_rollback_clarification ~ct ~file_path ~emit ~outcomes =
  let deferred =
    List.filter (fun (po : Version_finalize.prop_outcome) ->
      po.status <> "established") outcomes in
  if deferred = [] then ()
  else
    let questions =
      ("k4k completed a version that was rolled back. Edit the \
        user-owned sections below to refine the spec, or accept a \
        degraded tier when proposed.")
      :: List.map (fun (po : Version_finalize.prop_outcome) ->
           let r = match po.failure_reason with
             | Some s -> s
             | None -> "(no recorded reason)" in
           Printf.sprintf
             "Property %s deferred: %s" po.id r) deferred
    in
    try
      Cotype.append_clarification ct ~path:file_path ~questions;
      emit "clarification.rolled_back_summary"
        (`Assoc [ "deferred", `Int (List.length deferred);
                  "property_ids",
                  `List (List.map (fun (po : Version_finalize.prop_outcome) ->
                          `String po.id) deferred) ])
    with Error.K4k_error e ->
      emit "clarification.write_failed"
        (`Assoc [ "code", `String (Error.code_id e);
                  "render", `String (Error.render e); ])

let escalate_unsatisfiable_streak ~ct ~file_path ~emit ~streak =
  let questions = [
    Printf.sprintf
      "k4k rolled back %d versions in a row — the spec may be \
       unsatisfiable under the current backend (or the agent is \
       stuck in a local minimum). Suggested actions: (1) edit the \
       user-owned sections to make the goal more explicit / break \
       it into smaller acceptance examples; (2) when the next \
       tradeoff proposal arrives, accept a degraded tier; \
       (3) if you believe the spec is correct and the agent is at \
       fault, switch to a stronger backend (edit \
       .k4k/config.json's backend.command) and re-launch."
      streak;
  ] in
  try
    Cotype.append_clarification ct ~path:file_path ~questions;
    emit "version.unsatisfiable_streak"
      (`Assoc [ "streak", `Int streak;
                "threshold", `Int streak_threshold ])
  with Error.K4k_error e ->
    emit "clarification.write_failed"
      (`Assoc [ "code", `String (Error.code_id e);
                "render", `String (Error.render e); ])
