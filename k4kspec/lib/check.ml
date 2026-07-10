(* The reference-free spec-validation harness:
     - examples-checking      (the author's stated intent)
     - stability checks        (exhaustiveness, dead cases, anti-vacuity)
     - under-specification report (free observable dimensions, for sign-off)
     - adversarial sweep        (surface the spec's behavior on boundary inputs
                                 for the human to adjudicate)
   None of this needs a reference binary. A reference is an OPTIONAL plug (Refdiff). *)

open Ast

(* ---- byte display --------------------------------------------------------- *)
let esc (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c when Char.code c >= 32 && Char.code c < 127 -> Buffer.add_char b c
      | c -> Buffer.add_string b (Printf.sprintf "\\x%02x" (Char.code c)))
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let show_stderr = function Eval.SExact s -> esc s | Eval.SPred p ->
  (match p with OneNonemptyLine -> "~one-nonempty-line" | Nonempty -> "~nonempty" | EmptyB -> "\"\"" | Any -> "~any")

let argv_str a = "[" ^ String.concat "; " (List.map esc a) ^ "]"
let files_str fs = "{" ^ String.concat "; " (List.map (fun (p, c) -> p ^ "=" ^ esc c) fs) ^ "}"

(* a compact, human-readable rendering of a guard expression *)
let rec describe_expr (e : expr) : string =
  match e with
  | Lit (B s) -> esc s
  | Lit (I n) -> string_of_int n
  | Lit (Bool b) -> string_of_bool b
  | Lit _ -> "<lit>"
  | Argv i -> Printf.sprintf "argv[%d]" i
  | ArgvAll -> "argv"
  | Stdin -> "stdin"
  | FileBytes -> "file.bytes"
  | OStdout -> "stdout" | OStderr -> "stderr" | OExit -> "exit"
  | Var x -> x
  | If (c, a, b) -> Printf.sprintf "if %s then %s else %s" (describe_expr c) (describe_expr a) (describe_expr b)
  | Lam (x, b) -> Printf.sprintf "\\%s -> %s" x (describe_expr b)
  | App (f, args) -> describe_app f args
and describe_app f args =
  let bin op a b = Printf.sprintf "%s %s %s" (describe_expr a) op (describe_expr b) in
  match f, args with
  | "ne", [ a; b ] -> bin "!=" a b
  | "eq", [ a; b ] -> bin "==" a b
  | "lt", [ a; b ] -> bin "<" a b
  | "le", [ a; b ] -> bin "<=" a b
  | "gt", [ a; b ] -> bin ">" a b
  | "ge", [ a; b ] -> bin ">=" a b
  | "and", [ a; b ] -> bin "and" a b
  | "or", [ a; b ] -> bin "or" a b
  | "not", [ a ] -> "not " ^ describe_expr a
  | "absent_footprint", [] -> "file absent"
  | "present_footprint", [] -> "file present"
  | _ -> Printf.sprintf "%s(%s)" f (String.concat ", " (List.map describe_expr args))

let describe_guard = function None -> "otherwise" | Some g -> describe_expr g

(* ---- examples ------------------------------------------------------------- *)
type ex_result = Pass | Fail of string list | Err of string

let check_example sp (e : example) : ex_result =
  let inp = Eval.input_of e.ex_argv e.ex_files in
  match
    (try `Ok (Eval.run sp inp) with
     | Eval.Spec_error m -> `Err m
     | Eval.Undetermined idx ->
         `Err (Printf.sprintf "matches law-constrained case #%d: not oracle-checkable (proof-guaranteed via certify) — examples belong on the determined cases" idx))
  with
  | `Err m -> Err m
  | `Ok r ->
      let so = match e.ex_stdout with
        | Some exp when r.Eval.rstdout <> exp -> Some (Printf.sprintf "stdout: want %s got %s" (esc exp) (esc r.Eval.rstdout))
        | _ -> None in
      let eo = match e.ex_exit with
        | Some exp when r.Eval.rexit <> exp -> Some (Printf.sprintf "exit: want %d got %d" exp r.Eval.rexit)
        | _ -> None in
      (match List.filter_map Fun.id [ so; eo ] with [] -> Pass | xs -> Fail xs)

(* ---- adversarial input generator (heuristic, deterministic) --------------- *)
let arg_pool = [ "x"; ""; "-"; ","; "="; "2"; "0"; "1"; "q" ]
let content_pool = [ ""; "a"; "a\n"; "a\nb"; "a\nb\n"; "\n"; "a,b,c\n"; "k=1\nk=2\n" ]

(* mutation-based generation: perturb each author example towards its boundaries.
   These inputs sit NEXT TO the author's stated intent, so the spec's behavior on them
   is the most useful thing to put in front of the human for adjudication.
   [mutate_described] keeps a label per mutation so we can report what changed. *)
let toggle_nl c =
  if c <> "" && c.[String.length c - 1] = '\n' then String.sub c 0 (String.length c - 1) else c ^ "x"

let mutate_described (argv, files) : (string * (string list * (string * string) list)) list =
  let drop_last = match List.rev argv with _ :: r -> [ ("drop last arg", (List.rev r, files)) ] | [] -> [] in
  let add_arg = [ ("add an arg", (argv @ [ "x" ], files)) ] in
  let file_muts =
    List.concat_map
      (fun (p, c) ->
        let others = List.filter (fun (q, _) -> q <> p) files in
        [ (Printf.sprintf "empty %s" p, (argv, (p, "") :: others));
          (Printf.sprintf "drop trailing-nl in %s" p, (argv, (p, toggle_nl c) :: others));
          (Printf.sprintf "remove %s" p, (argv, others)) ])
      files
  in
  drop_last @ add_arg @ file_muts

let example_mutations (sp : spec) : (string list * (string * string) list) list =
  List.concat_map (fun e -> List.map snd (mutate_described (e.ex_argv, e.ex_files))) sp.examples

(* a scenario is (argv, present-files) *)
let scenarios (sp : spec) : (string list * (string * string) list) list =
  let from_examples = List.map (fun e -> (e.ex_argv, e.ex_files)) sp.examples in
  let nth_pool i = List.nth arg_pool (i mod List.length arg_pool) in
  let gen =
    match sp.reads with
    | FileAtEach ->
        (* variadic: lists of file names, some present some absent *)
        let present c = [ ("F1", c); ("F2", "B\n") ] in
        List.concat_map
          (fun c ->
            [ ([], []);
              ([ "F1" ], present c);
              ([ "F1"; "F2" ], present c);
              ([ "F1"; "missing" ], present c);
              ([ "missing" ], present c) ])
          content_pool
    | reads ->
        let fidx = match reads with FileAt i -> Some i | _ -> None in
        List.concat_map
          (fun len ->
            let base = List.init len nth_pool in
            match fidx with
            | Some i when i < len ->
                List.concat_map
                  (fun c ->
                    let with_file = List.mapi (fun j v -> if j = i then "F" else v) base in
                    [ (with_file, [ ("F", c) ]); (with_file, []) (* absent *) ])
                  content_pool
            | _ -> [ (base, []) ])
          [ 0; 1; 2; 3 ]
  in
  (* dedup, keep order, cap *)
  let seen = Hashtbl.create 97 in
  List.filter
    (fun s -> let k = Marshal.to_string s [] in if Hashtbl.mem seen k then false else (Hashtbl.add seen k (); true))
    (from_examples @ example_mutations sp @ gen)

(* ---- stability ------------------------------------------------------------ *)
let has_otherwise sp = List.exists (fun c -> c.guard = None) sp.cases

(* channels left free (predicate, not pinned) — the under-spec report *)
let free_dims (sp : spec) : (int * chan * pred) list =
  List.concat (List.mapi (fun idx c ->
      List.filter_map (fun (ch, r) -> match r with P p -> Some (idx, ch, p) | Eq _ -> None) c.outs) sp.cases)

let chan_name = function Stdout -> "stdout" | Stderr -> "stderr" | Exit -> "exit"

(* does this (law) expression mention the given OUTPUT channel? *)
let rec law_mentions ch (e : expr) =
  match e with
  | OStdout -> ch = Stdout | OStderr -> ch = Stderr | OExit -> ch = Exit
  | App (_, xs) -> List.exists (law_mentions ch) xs
  | Lam (_, b) -> law_mentions ch b
  | If (a, b, c) -> law_mentions ch a || law_mentions ch b || law_mentions ch c
  | Lit _ | Argv _ | ArgvAll | Stdin | FileBytes | Var _ -> false
let pred_name = function OneNonemptyLine -> "one-nonempty-line" | Nonempty -> "nonempty" | EmptyB -> "empty" | Any -> "ANY (unconstrained)"

(* ---- the report ----------------------------------------------------------- *)
(* quiet form: (validates?, full report text) — used by sign/propose gates *)
let report (sp : spec) : bool * string =
  let buf = Buffer.create 1024 in
  let p fmt = Printf.ksprintf (fun s -> Buffer.add_string buf s; Buffer.add_char buf '\n') fmt in
  p "=== k4kspec check: %s ===" sp.name;

  (* examples *)
  let results = List.map (check_example sp) sp.examples in
  let passed = List.length (List.filter (fun r -> r = Pass) results) in
  p "";
  p "[examples] %d/%d passed" passed (List.length results);
  List.iteri (fun k (e, r) -> match r with
      | Pass -> ()
      | Fail xs -> p "  FAIL #%d argv=%s files=%s : %s" k (argv_str e.ex_argv) (files_str e.ex_files) (String.concat "; " xs)
      | Err m -> p "  ERR  #%d argv=%s : %s" k (argv_str e.ex_argv) m)
    (List.combine sp.examples results);

  (* stability via the sweep *)
  let scen = scenarios sp in
  let traced = List.map (fun (argv, files) ->
      let inp = Eval.input_of argv files in
      ((argv, files),
       try `Ok (Eval.run_traced sp inp) with
       | Eval.Undetermined idx -> `Undet idx
       | Eval.Spec_error m -> `Err m)) scen in
  let nonexhaustive = List.filter (function (_, `Err _) -> true | _ -> false) traced in
  let undet = List.filter_map (function (_, `Undet idx) -> Some idx | _ -> None) traced in
  let fired = undet @ List.filter_map (function (_, `Ok (_, idx)) -> Some idx | _ -> None) traced in
  let dead = List.filter (fun idx -> not (List.mem idx fired)) (List.init (List.length sp.cases) Fun.id) in
  (* a P Any channel is VACUOUS only if no relational law of its case mentions it *)
  let law_constrained idx ch = List.exists (law_mentions ch) (List.nth sp.cases idx).laws in
  let anys = List.filter (fun (_, _, p) -> p = Any) (free_dims sp) in
  let vacuous, lawful = List.partition (fun (idx, ch, _) -> not (law_constrained idx ch)) anys in
  p "";
  p "[stability]";
  p "  exhaustiveness (static): %s" (if has_otherwise sp then "OK (otherwise present)" else "WARN: no otherwise");
  p "  exhaustiveness (swept %d inputs): %s" (List.length scen)
    (if nonexhaustive = [] then "OK (all matched a case)"
     else Printf.sprintf "FAIL: %d input(s) matched NO case" (List.length nonexhaustive));
  List.iter (fun ((argv, files), _) -> p "      no-match: argv=%s files=%s" (argv_str argv) (files_str files)) nonexhaustive;
  if undet <> [] then
    p "  law-constrained inputs: %d (matched a law case; output proof-guaranteed via `certify`, not oracle-checkable)"
      (List.length undet);
  p "  dead cases (heuristic, over sweep): %s" (if dead = [] then "none" else String.concat ", " (List.map (Printf.sprintf "#%d") dead));
  p "  anti-vacuity: %s" (if vacuous = [] then "OK (no fully-unconstrained channel)"
                          else String.concat "; " (List.map (fun (idx, ch, _) -> Printf.sprintf "WARN case #%d %s is ANY" idx (chan_name ch)) vacuous));
  List.iter (fun (idx, ch, _) ->
      p "    case #%d %s is ANY but constrained by %d law(s) — content certified, not validated here"
        idx (chan_name ch) (List.length (List.nth sp.cases idx).laws)) lawful;

  (* under-specified dimensions — surfaced for explicit sign-off *)
  p "";
  p "[under-specified dimensions]  (content agent-authored, NOT certified — intended?)";
  (match free_dims sp with
   | [] -> p "  none — every channel is pinned"
   | ds -> List.iter (fun (idx, ch, pr) ->
       if pr = Any && law_constrained idx ch then
         p "  case #%d  %s : law-constrained (%d law(s); see [stability])" idx (chan_name ch)
           (List.length (List.nth sp.cases idx).laws)
       else p "  case #%d  %s : free (%s)" idx (chan_name ch) (pred_name pr)) ds);

  (* curated validation surface: per-case representatives + behavior-changing mutations.
     A flat dump of every swept input defeats human review (rubber-stamping); we surface
     one representative per distinct behavior, and the mutations that actually changed it. *)
  let oks = List.filter_map (function ((a, f), `Ok (r, idx)) -> Some (a, f, r, idx) | _ -> None) traced in
  p "";
  p "[validation surface]  (curated; full sweep = %d inputs)" (List.length scen);
  p "  by case (one representative per distinct behavior):";
  List.iteri (fun idx (c : case) ->
      let rows = List.filter (fun (_, _, _, i) -> i = idx) oks in
      if rows <> [] then begin
        let seen = Hashtbl.create 8 in
        let reps = List.filter (fun (_, _, r, _) ->
            let k = (r.Eval.rexit, r.Eval.rstdout = "", show_stderr r.Eval.rstderr) in
            if Hashtbl.mem seen k then false else (Hashtbl.add seen k (); true)) rows in
        p "    case #%d  [%s]  — %d input(s)" idx (describe_guard c.guard) (List.length rows);
        List.iter (fun (a, f, r, _) ->
            p "        -> exit=%d stdout=%s stderr=%s   e.g. argv=%s files=%s"
              r.Eval.rexit (esc r.Eval.rstdout) (show_stderr r.Eval.rstderr) (argv_str a) (files_str f)) reps
      end)
    sp.cases;

  (* mutations of the author's examples that CHANGED observable behavior *)
  let run_opt inp = try Some (Eval.run sp inp) with Eval.Spec_error _ | Eval.Undetermined _ -> None in
  let surprises =
    List.concat (List.mapi (fun k e ->
        match run_opt (Eval.input_of e.ex_argv e.ex_files) with
        | None -> []
        | Some base ->
            List.filter_map (fun (desc, (a, f)) ->
                match run_opt (Eval.input_of a f) with
                | Some m when (m.Eval.rstdout, m.Eval.rexit) <> (base.Eval.rstdout, base.Eval.rexit) ->
                    Some (k, desc, base, m, a, f)
                | _ -> None)
              (mutate_described (e.ex_argv, e.ex_files)))
      sp.examples)
  in
  let shown = List.filteri (fun i _ -> i < 8) surprises in
  p "";
  if surprises = [] then
    p "  boundary surprises: none (perturbing your examples changed nothing observable)"
  else begin
    p "  boundary surprises  (a mutation of an example CHANGED behavior — review these):";
    List.iter (fun (k, desc, base, m, a, f) ->
        p "    ex#%d + [%s]: exit %d->%d  stdout %s->%s   (argv=%s files=%s)"
          k desc base.Eval.rexit m.Eval.rexit (esc base.Eval.rstdout) (esc m.Eval.rstdout) (argv_str a) (files_str f))
      shown;
    if List.length surprises > 8 then p "    ... and %d more" (List.length surprises - 8)
  end;

  (* overall pass = all examples pass, exhaustive, no fully-vacuous channel *)
  let ok = passed = List.length results && nonexhaustive = [] && vacuous = [] in
  (ok, Buffer.contents buf)

let run_report (sp : spec) : bool =
  let ok, s = report sp in
  print_string s;
  ok
