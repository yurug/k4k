(** [Backend_canned] — load a sequence of canned agent responses from a
    JSON file (via [K4K_STUB_RESPONSES]).

    Each invocation pops the next response whose purpose matches; the
    queue is per-purpose so [Formalization] requests don't consume
    [Gap_step] entries and vice versa. This is the test-only knob the
    integration suite uses to drive [Version_loop] end-to-end without
    a real LLM. *)

type entry = {
  purpose : Agent_backend.purpose;
  text : string;
}

type t = {
  mutable formalize : entry list;
  mutable gap_step  : entry list;
  mutable kb_regen  : entry list;
}

let purpose_of = function
  | "Formalization" -> Some `Formalization
  | "Gap_step" -> Some `Gap_step
  | "Kb_regen" -> Some `Kb_regen
  | _ -> None

let parse_entries (j : Yojson.Safe.t) : entry list =
  match j with
  | `List items ->
      List.filter_map (fun (item : Yojson.Safe.t) ->
        match item with
        | `Assoc fs ->
            let p = match List.assoc_opt "purpose" fs with
              | Some (`String s) -> purpose_of s | _ -> None in
            let t = match List.assoc_opt "text" fs with
              | Some (`String s) -> Some s | _ -> None in
            (match p, t with
             | Some purpose, Some text -> Some { purpose; text }
             | _ -> None)
        | _ -> None) items
  | _ -> []

let load_from_path path : (t, string) result =
  try
    let raw = Persist.read_file path in
    let j = Yojson.Safe.from_string raw in
    let all = parse_entries j in
    let by_purpose target =
      List.filter (fun e -> e.purpose = target) all in
    Ok { formalize = by_purpose `Formalization;
         gap_step  = by_purpose `Gap_step;
         kb_regen  = by_purpose `Kb_regen; }
  with
  | Sys_error msg -> Error msg
  | Yojson.Json_error msg -> Error msg
  | Error.K4k_error e -> Error (Error.render e)

let queue_for t = function
  | `Formalization -> ref t.formalize
  | `Gap_step -> ref t.gap_step
  | `Kb_regen -> ref t.kb_regen

let pop t purpose : entry option =
  let assign rest = match purpose with
    | `Formalization -> t.formalize <- rest
    | `Gap_step -> t.gap_step <- rest
    | `Kb_regen -> t.kb_regen <- rest
  in
  let q = !(queue_for t purpose) in
  match q with
  | [] -> None
  | hd :: tl -> assign tl; Some hd

let invoke t ~purpose ~prompt:_ ~budget:_ : Agent_backend.result =
  match pop t purpose with
  | None ->
      `Tool_error "canned: no response left for purpose"
  | Some e ->
      `Ok Agent_backend.{ text = e.text;
                          budget_used = 0; duration_ms = 0 }
