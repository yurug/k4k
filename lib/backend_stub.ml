type response_entry = {
  purpose : Agent_backend.purpose;
  trigger : string -> bool;
  payload : (string, [ `Budget_exhausted | `Tool_error of string ]) result;
}

type config = { responses : response_entry list }

type t = { cfg : config }

let name = "stub"

let version _t = "0.1.0-stub"

let create cfg = { cfg }

let invoke t ~purpose ~prompt ~budget =
  let _ = budget in
  let matching =
    List.find_opt (fun e ->
      e.purpose = purpose && e.trigger prompt
    ) t.cfg.responses
  in
  match matching with
  | None ->
      `Tool_error "stub: step 1 doesn't call agents"
  | Some { payload = Ok text; _ } ->
      `Ok Agent_backend.{ text; budget_used = 0; duration_ms = 0 }
  | Some { payload = Error `Budget_exhausted; _ } ->
      `Budget_exhausted
  | Some { payload = Error (`Tool_error s); _ } ->
      `Tool_error s
