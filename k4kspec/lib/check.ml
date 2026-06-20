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

(* ---- examples ------------------------------------------------------------- *)
type ex_result = Pass | Fail of string list | Err of string

let check_example sp (e : example) : ex_result =
  let inp = Eval.input_of e.ex_argv e.ex_files in
  match (try `Ok (Eval.run sp inp) with Eval.Spec_error m -> `Err m) with
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
    (from_examples @ gen)

(* ---- stability ------------------------------------------------------------ *)
let has_otherwise sp = List.exists (fun c -> c.guard = None) sp.cases

(* channels left free (predicate, not pinned) — the under-spec report *)
let free_dims (sp : spec) : (int * chan * pred) list =
  List.concat (List.mapi (fun idx c ->
      List.filter_map (fun (ch, r) -> match r with P p -> Some (idx, ch, p) | Eq _ -> None) c.outs) sp.cases)

let chan_name = function Stdout -> "stdout" | Stderr -> "stderr" | Exit -> "exit"
let pred_name = function OneNonemptyLine -> "one-nonempty-line" | Nonempty -> "nonempty" | EmptyB -> "empty" | Any -> "ANY (unconstrained)"

(* ---- the report ----------------------------------------------------------- *)
let run_report (sp : spec) : bool =
  let p fmt = Printf.ksprintf (fun s -> print_string s; print_newline ()) fmt in
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
      ((argv, files), try `Ok (Eval.run_traced sp inp) with Eval.Spec_error m -> `Err m)) scen in
  let nonexhaustive = List.filter (function (_, `Err _) -> true | _ -> false) traced in
  let fired = List.filter_map (function (_, `Ok (_, idx)) -> Some idx | _ -> None) traced in
  let dead = List.filter (fun idx -> not (List.mem idx fired)) (List.init (List.length sp.cases) Fun.id) in
  let vacuous = List.filter (fun (_, _, p) -> p = Any) (free_dims sp) in
  p "";
  p "[stability]";
  p "  exhaustiveness (static): %s" (if has_otherwise sp then "OK (otherwise present)" else "WARN: no otherwise");
  p "  exhaustiveness (swept %d inputs): %s" (List.length scen)
    (if nonexhaustive = [] then "OK (all matched a case)"
     else Printf.sprintf "FAIL: %d input(s) matched NO case" (List.length nonexhaustive));
  List.iter (fun ((argv, files), _) -> p "      no-match: argv=%s files=%s" (argv_str argv) (files_str files)) nonexhaustive;
  p "  dead cases (heuristic, over sweep): %s" (if dead = [] then "none" else String.concat ", " (List.map (Printf.sprintf "#%d") dead));
  p "  anti-vacuity: %s" (if vacuous = [] then "OK (no fully-unconstrained channel)"
                          else String.concat "; " (List.map (fun (idx, ch, _) -> Printf.sprintf "WARN case #%d %s is ANY" idx (chan_name ch)) vacuous));

  (* under-specified dimensions — surfaced for explicit sign-off *)
  p "";
  p "[under-specified dimensions]  (content agent-authored, NOT certified — intended?)";
  (match free_dims sp with
   | [] -> p "  none — every channel is pinned"
   | ds -> List.iter (fun (idx, ch, pr) -> p "  case #%d  %s : free (%s)" idx (chan_name ch) (pred_name pr)) ds);

  (* adversarial sweep — the human-as-oracle adjudication surface *)
  p "";
  p "[adversarial sweep]  (review: is this what you meant on these inputs?)";
  List.iter (fun ((argv, files), r) -> match r with
      | `Err m -> p "  argv=%s files=%s -> ERROR: %s" (argv_str argv) (files_str files) m
      | `Ok (res, idx) ->
          p "  argv=%-22s files=%-26s -> stdout=%s exit=%d stderr=%s [case #%d]"
            (argv_str argv) (files_str files) (esc res.Eval.rstdout) res.Eval.rexit (show_stderr res.Eval.rstderr) idx)
    traced;

  (* overall pass = all examples pass, exhaustive, no fully-vacuous channel *)
  passed = List.length results && nonexhaustive = [] && vacuous = []
