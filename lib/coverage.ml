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

(* T2: two acceptance examples with the same (argv, stdin) but
   different expected outputs are mutually contradictory.
   Stability rejects with a clarification naming both examples. *)
let conflicting_accept_pairs
    (xs : Characterization.acceptance_example list)
    : (string * string) list =
  let key (e : Characterization.acceptance_example) =
    String.concat "\x1f" e.argv ^ "\x1c"
    ^ (match e.stdin with None -> "<none>" | Some s -> s) in
  let buckets = Hashtbl.create 16 in
  List.iter (fun (e : Characterization.acceptance_example) ->
    let k = key e in
    Hashtbl.add buckets k e) xs;
  let conflicts = ref [] in
  Hashtbl.iter (fun _ _ -> ()) buckets;  (* force eval *)
  let seen = Hashtbl.create 16 in
  List.iter (fun (e : Characterization.acceptance_example) ->
    let k = key e in
    if not (Hashtbl.mem seen k) then begin
      Hashtbl.add seen k ();
      let group = Hashtbl.find_all buckets k in
      let same (a : Characterization.acceptance_example)
               (b : Characterization.acceptance_example) =
        a.expect = b.expect in
      let rec pairs = function
        | [] | [_] -> []
        | a :: rest ->
            List.filter_map (fun b ->
              if same a b then None
              else Some (a.name, b.name)) rest
            @ pairs rest
      in
      List.iter (fun p -> conflicts := p :: !conflicts) (pairs group)
    end) xs;
  List.rev !conflicts

let check_cli (c : Characterization.t) : Error.issue list =
  let issues = ref [] in
  let add a = issues := issue_for a :: !issues in
  let add_msg ~section msg =
    issues := Error.issue ~section msg :: !issues in
  if is_blank c.goal then add "goal";
  if c.inputs_outputs.exit_codes = [] then add "inputs_outputs.exit_codes";
  if List.length c.examples_accept < 3 then add "examples_accept";
  if c.examples_refuse = [] then add "examples_refuse";
  (* T2: conflicting acceptance examples. *)
  List.iter (fun (a, b) ->
    add_msg ~section:"examples_accept"
      (Printf.sprintf
         "T2: %s and %s have the same (argv, stdin) but different \
          expected output — mutually contradictory" a b)
  ) (conflicting_accept_pairs c.examples_accept);
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
