(** [Property] — runtime representation of a Property record per
    [kb/spec/data-model.md#property], plus pure derivation helpers
    (gap construction, risk score) per [algorithms.md].

    No I/O. Persistence lives in [Persist.write_gap]. *)

type status =
  [ `Required | `Established | `Contradicted | `Unknown ]

type artefact_kind = [ `Agent_run | `Verifier_run ]

type artefact_ref = {
  kind : artefact_kind;
  ref_id : string;
}

type aspect_ref = {
  aspect : string;
  path   : string list;
}

type t = {
  id            : string;
  statement     : string;
  status        : status;
  evidence      : artefact_ref list;
  risk_score    : float;
  failure_count : int;
  source        : aspect_ref;
}

(* --- severity table per spec/algorithms.md#risk-score --- *)
let severity_table = [
  "errors",          1.0;
  "fs_contract",     0.9;
  "exit_codes",      0.8;
  "examples_refuse", 0.8;
  "inputs_outputs",  0.7;
  "examples_accept", 0.6;
  "concurrency",     0.5;
  "perf",            0.4;
  "goal",            0.2;
  "out_of_scope",    0.2;
]

let severity_of aspect =
  try List.assoc aspect severity_table with Not_found -> 0.2

let blast_of (s : aspect_ref) : float =
  match s.aspect with
  | "examples_accept" | "examples_refuse" -> 0.5
  | _ -> 1.0

let uncertainty_of = function
  | `Unknown -> 1.0
  | `Contradicted -> 0.5
  | `Established -> 0.0
  | `Required -> 1.0

let risk_score (p : t) : float =
  severity_of p.source.aspect
  *. uncertainty_of p.status
  *. blast_of p.source

(** [argmax_lex ps] selects the property with the highest [risk_score];
    lexicographic order of [id] breaks ties.
    @return [Some p] or [None] when [ps] is empty. *)
let argmax_lex (ps : t list) : t option =
  let cmp a b =
    let c = compare b.risk_score a.risk_score in
    if c <> 0 then c else compare a.id b.id
  in
  match List.sort cmp ps with
  | [] -> None
  | hd :: _ -> Some hd

let with_status p st = { p with status = st; risk_score = 0.0 }

let regen_risk p = { p with risk_score = risk_score p }

(** Increment failure count. Three-strikes (fc=3) is the signal
    [Gap_step] uses to emit the [Tradeoff] outcome; the property
    record itself stops carrying a redundant [blocked] mirror. *)
let bump_failure p =
  { p with failure_count = p.failure_count + 1 }

(* --- aspect derivation per algorithms.md#gap-construction --- *)

let aspect_paths_of (d : Characterization.t) : aspect_ref list =
  let acc = ref [] in
  let add aspect path =
    acc := { aspect; path } :: !acc
  in
  add "goal" ["goal"];
  if d.inputs_outputs.argv <> [] then
    List.iter (fun (a : Characterization.arg_spec) ->
      add "inputs_outputs" ["argv"; a.name]) d.inputs_outputs.argv;
  if d.inputs_outputs.exit_codes <> [] then
    List.iter (fun (e : Characterization.exit_code_entry) ->
      add "exit_codes" ["exit_codes"; string_of_int e.code])
      d.inputs_outputs.exit_codes;
  List.iter (fun (e : Characterization.error_entry) ->
    add "errors" ["errors"; e.id]) d.errors;
  List.iter (fun (a : Characterization.acceptance_example) ->
    add "examples_accept" ["examples_accept"; a.name]) d.examples_accept;
  List.iter (fun (r : Characterization.refusing_example) ->
    add "examples_refuse" ["examples_refuse"; r.name]) d.examples_refuse;
  List.rev !acc

let statement_of_aspect (d : Characterization.t) (s : aspect_ref) : string =
  match s.aspect, s.path with
  | "goal", _ -> Printf.sprintf "Goal: %s" d.goal
  | "inputs_outputs", ["argv"; n] ->
      Printf.sprintf "argv handles %s correctly" n
  | "exit_codes", [_; c] ->
      Printf.sprintf "exits with code %s under documented condition" c
  | "errors", [_; id] ->
      Printf.sprintf "raises error %s under documented condition" id
  | "examples_accept", [_; n] ->
      Printf.sprintf "acceptance example %s passes" n
  | "examples_refuse", [_; n] ->
      Printf.sprintf "refusing example %s is rejected" n
  | _ -> Printf.sprintf "%s/%s" s.aspect (String.concat "/" s.path)

let make ~source ~statement ?(status = `Required)
    ?(evidence = []) ?(failure_count = 0) () =
  let id = Property_id.of_path source.path in
  let p = { id; statement; status; evidence;
            risk_score = 0.0; failure_count; source } in
  regen_risk p

let from_characterization (d : Characterization.t) : t list =
  List.map (fun src ->
    make ~source:src ~statement:(statement_of_aspect d src) ()
  ) (aspect_paths_of d)
