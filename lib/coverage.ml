(** [Coverage] — class-keyed coverage-checklist enforcement on [D].

    Per [kb/spec/data-model.md#coverage-checklists]: an interaction file
    is stable iff every aspect listed for its class is mentioned
    non-trivially. v0 ships only the [cli] checklist. *)

let issue_for aspect =
  Error.issue ~section:aspect
    "coverage-checklist: aspect mentioned trivially or missing"

let is_blank s =
  let len = String.length s in
  let rec loop i =
    if i >= len then true
    else match s.[i] with
      | ' ' | '\t' | '\n' | '\r' -> loop (i + 1)
      | _ -> false
  in
  loop 0

let check_cli (c : Characterization.t) : Error.issue list =
  let issues = ref [] in
  let add a = issues := issue_for a :: !issues in
  if is_blank c.goal then add "goal";
  if c.inputs_outputs.exit_codes = [] then add "inputs_outputs.exit_codes";
  if List.length c.examples_accept < 3 then add "examples_accept";
  if c.examples_refuse = [] then add "examples_refuse";
  (* errors / fs_contract / concurrency / perf / out_of_scope can be
     "N/A" (empty), but the underlying user-section was already checked
     to be non-empty by structural stability. *)
  if c.inputs_outputs.stdout.doc = "" && c.inputs_outputs.stdout.kind = `None
  then add "inputs_outputs.stdout";
  List.rev !issues

let check (c : Characterization.t) : Error.issue list =
  match c.cls with
  | "cli" -> check_cli c
  | other ->
      [ Error.issue ~section:"class"
          (Printf.sprintf "unsupported class: %s (v0 supports: cli)" other) ]
