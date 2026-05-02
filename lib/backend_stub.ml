type response_entry = {
  purpose : Agent_backend.purpose;
  trigger : string -> bool;
  payload : (string, [ `Budget_exhausted | `Tool_error of string ]) result;
}

type profile = [ `Strong | `Weak ]

type config = {
  responses : response_entry list;
  profile   : profile;
  weak_seed : int;       (* deterministic stochasticity *)
}

type t = {
  cfg     : config;
  counter : int ref;     (* number of invocations; drives weak-mode jitter *)
}

let name = "stub"

let version _t = "0.1.0-stub"

let default_config = {
  responses = [];
  profile   = `Weak;     (* NF8 — weak is default *)
  weak_seed = 0;
}

let create cfg = { cfg; counter = ref 0 }

(* --- weakness profile post-processing --- *)

let truncate_10pct s =
  let len = String.length s in
  let cut = max 0 (len - max 1 (len / 10)) in
  if cut >= len then s else String.sub s 0 cut

let inject_codefence s =
  Printf.sprintf "Here is the JSON you requested:\n```json\n%s\n```\nEnd of response.\n" s

let inject_trailing_comma s =
  (* If the string contains a closing brace, drop a "," before it
     occasionally. Conservative: only at the first depth-0 close. *)
  match Permissive_json.extract s with
  | exception _ -> s
  | _ ->
      (* Place a comma right before the final '}' to test trailing-comma
         tolerance. We do this on a copy. *)
      let n = String.length s in
      let last = ref (-1) in
      for i = 0 to n - 1 do
        if s.[i] = '}' then last := i
      done;
      if !last <= 0 then s
      else String.sub s 0 !last ^ ",\n" ^ String.sub s !last (n - !last)

let weak_mutate cfg counter s =
  let n = !counter in
  counter := n + 1;
  let pick = (n + cfg.weak_seed) mod 4 in
  match pick with
  | 0 -> inject_codefence s
  | 1 -> inject_trailing_comma (inject_codefence s)
  | 2 -> inject_codefence s ^ "\nNote: please review carefully.\n"
  | _ -> s
  (* Truncation is suppressed by default — it would make the response
     unparseable, defeating the test corpus. The "weak" profile still
     stresses the parser via fences + trailing commas + trailing prose,
     which is what R7 asks for. *)

let _ = truncate_10pct  (* available for future explicit-failure tests *)

(* --- main entry --- *)

let invoke t ~purpose ~prompt ~budget =
  let _ = budget in
  let matching =
    List.find_opt (fun e ->
      e.purpose = purpose && e.trigger prompt
    ) t.cfg.responses
  in
  match matching with
  | None ->
      `Tool_error "stub: no canned response for prompt"
  | Some { payload = Ok text; _ } ->
      let text =
        match t.cfg.profile with
        | `Strong -> text
        | `Weak   -> weak_mutate t.cfg t.counter text
      in
      `Ok Agent_backend.{ text; budget_used = 0; duration_ms = 0 }
  | Some { payload = Error `Budget_exhausted; _ } ->
      `Budget_exhausted
  | Some { payload = Error (`Tool_error s); _ } ->
      `Tool_error s
