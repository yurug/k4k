(* stdlib-only test runner (no alcotest dependency). Exits 1 on any failure. *)
open K4kspec

let fails = ref 0
let check name cond = if not cond then (incr fails; Printf.printf "FAIL  %s\n" name)
let eqs name got want =
  if got <> want then (incr fails; Printf.printf "FAIL  %s: got %S want %S\n" name got want)
let eqi name got want =
  if got <> want then (incr fails; Printf.printf "FAIL  %s: got %d want %d\n" name got want)

let lst xs = String.concat "," (List.map (fun s -> "<" ^ s ^ ">") xs)

let () =
  let open Algebra in
  (* lines: the documented POSIX convention *)
  eqs "lines empty"       (lst (lines ""))         "";
  eqs "lines a\\nb\\n"    (lst (lines "a\nb\n"))    "<a>,<b>";
  eqs "lines a\\nb"       (lst (lines "a\nb"))      "<a>,<b>";
  eqs "lines a\\n\\nb\\n" (lst (lines "a\n\nb\n"))  "<a>,<>,<b>";
  eqs "lines \\n"         (lst (lines "\n"))        "<>";
  (* unlines is the inverse for the common case *)
  eqs "unlines []"        (unlines [])              "";
  eqs "unlines [a;b]"     (unlines [ "a"; "b" ])    "a\nb\n";
  check "lines/unlines roundtrip" (unlines (lines "a\nb\n") = "a\nb\n");
  (* split is mechanical (keeps every piece) *)
  eqs "split a,b,"        (lst (split "a,b," ","))  "<a>,<b>,<>";
  eqs "split empty"       (lst (split "" ","))      "<>";
  eqs "split nosep"       (lst (split "abc" ","))   "<abc>";
  (* contains *)
  check "contains b"      (contains "abc" "b");
  check "contains empty"  (contains "abc" "");
  check "contains miss"   (not (contains "abc" "z"));
  (* parse *)
  eqi "int_of 12"         (int_of "12")             12;
  eqi "int_of garbage"    (int_of "x")              0;
  check "is_decimal 12"   (is_decimal "12");
  check "is_decimal empty" (not (is_decimal ""));
  check "is_decimal 1a"   (not (is_decimal "1a"));
  (* ascii case folding (byte-wise; >=128 untouched) *)
  eqs "ascii_upper"       (ascii_upper "aZ9!")      "AZ9!";
  eqs "ascii_upper hi-byte" (ascii_upper "\xe9")    "\xe9";

  (* oracle sanity *)
  let r = Eval.run Specs.grepf (Eval.input_of [ "b"; "f" ] [ ("f", "a\nbob\ncab\n") ]) in
  eqs "grepf stdout" r.Eval.rstdout "bob\ncab\n";
  eqi "grepf exit" r.Eval.rexit 0;

  (* the DETERMINED-output specs only — the Eval oracle can't model under-determined / relational
     specs (e.g. bsort, whose stdout is constrained only by a sort law); those are guaranteed by
     the proof and exercised via `certify-agent`, not the oracle. *)
  let det_specs =
    List.filter
      (fun (sp : Ast.spec) -> List.for_all (fun (c : Ast.case) -> List.for_all (fun (_, r) -> r <> Ast.P Ast.Any) c.outs) sp.cases)
      Specs.all
  in
  (* every determined spec: all author examples must pass *)
  List.iter
    (fun (sp : Ast.spec) ->
      List.iteri
        (fun k e ->
          match Check.check_example sp e with
          | Check.Pass -> ()
          | Check.Fail xs -> incr fails; Printf.printf "FAIL  example %s#%d: %s\n" sp.name k (String.concat "; " xs)
          | Check.Err m -> incr fails; Printf.printf "FAIL  example %s#%d: %s\n" sp.name k m)
        sp.examples)
    det_specs;

  (* every spec: the adversarial sweep must be exhaustive (no input matches no case) *)
  List.iter
    (fun (sp : Ast.spec) ->
      List.iter
        (fun (argv, files) ->
          match Eval.run_traced sp (Eval.input_of argv files) with
          | _ -> ()
          | exception Eval.Undetermined _ -> ()   (* matched a law case: exhaustive, just not determined *)
          | exception Eval.Spec_error _ ->
              incr fails; Printf.printf "FAIL  %s non-exhaustive on argv=%s\n" sp.name (lst argv))
        (Check.scenarios sp))
    det_specs;

  (* round-trip: parse each surface .k4kspec and assert it behaves IDENTICALLY to the
     trusted AST spec (a wrong parser would be a wrong validator). *)
  let read_surface name =
    let cands = [ "k4kspec/examples/"; "../examples/"; "examples/" ] in
    match List.find_opt (fun d -> Sys.file_exists (d ^ name)) cands with
    | Some d -> let ic = open_in_bin (d ^ name) in
        let s = really_input_string ic (in_channel_length ic) in close_in ic; s
    | None -> incr fails; Printf.printf "FAIL  cannot find %s\n" name; ""
  in
  List.iter
    (fun (file, (ast : Ast.spec)) ->
      match (try `Ok (Parse.parse (read_surface file)) with Parse.Parse_error m -> `Err m) with
      | `Err m -> incr fails; Printf.printf "FAIL  parse %s: %s\n" file m
      | `Ok parsed ->
          if parsed.Ast.examples <> ast.Ast.examples then
            (incr fails; Printf.printf "FAIL  %s: parsed examples differ from the AST spec\n" file);
          if List.length parsed.Ast.cases <> List.length ast.Ast.cases then
            (incr fails; Printf.printf "FAIL  %s: case count differs\n" file);
          (* laws are invisible to the behavioral sweep (Eval raises Undetermined first):
             compare them structurally *)
          if List.map (fun (c : Ast.case) -> c.Ast.laws) parsed.Ast.cases
             <> List.map (fun (c : Ast.case) -> c.Ast.laws) ast.Ast.cases then
            (incr fails; Printf.printf "FAIL  %s: parsed laws differ from the AST spec\n" file);
          (* the decisive oracle: byte-identical certified statement (spec_rel) *)
          (match
             (try `Ok (Rocq_emit.emit_statement parsed) with Failure m -> `Err m),
             (try `Ok (Rocq_emit.emit_statement ast) with Failure m -> `Err m)
           with
           | `Ok a, `Ok b when a = b -> ()
           | `Ok _, `Ok _ -> incr fails; Printf.printf "FAIL  %s: emitted spec_rel differs from the AST spec's\n" file
           | `Err m, _ | _, `Err m -> incr fails; Printf.printf "FAIL  %s: emit_statement: %s\n" file m);
          List.iter
            (fun (argv, files) ->
              let inp = Eval.input_of argv files in
              let a = (try Some (Eval.run_traced ast inp) with _ -> None) in
              let b = (try Some (Eval.run_traced parsed inp) with _ -> None) in
              if a <> b then
                (incr fails; Printf.printf "FAIL  %s: round-trip behaviour differs on argv=%s\n" file (lst argv)))
            (Check.scenarios ast))
    [ ("grepf.k4kspec", Specs.grepf); ("cutf.k4kspec", Specs.cutf);
      ("catf.k4kspec", Specs.catf); ("kvget.k4kspec", Specs.kvget);
      ("bsort.k4kspec", Specs.bsort); ("partition.k4kspec", Specs.partition);
      ("usort.k4kspec", Specs.usort); ("grepsort.k4kspec", Specs.grepsort) ];

  (* ---- law parsing units ---------------------------------------------------- *)
  let mini_spec laws_and_stmts =
    "interface cli \"t\":\n  reads: nothing\ncases on argv:\n  when len(argv) != 1: exit 2 ; stderr: one nonempty line ; stdout: \"\"\n  otherwise:\n"
    ^ laws_and_stmts ^ "\nexamples:\n  argv=[] -> exit=2\n"
  in
  (match Parse.parse (mini_spec "    stdout: any\n    stderr: \"\"\n    exit: 0\n    law permutation(lines(stdout), matched)") with
   | sp ->
       (match (List.nth sp.Ast.cases 1).Ast.laws with
        | [ Ast.App ("permutation", [ Ast.App ("lines", [ Ast.OStdout ]); Ast.Var "matched" ]) ] -> ()
        | _ -> incr fails; print_endline "FAIL  law-parse: wrong AST for permutation(lines(stdout), matched)")
   | exception Parse.Parse_error m -> incr fails; Printf.printf "FAIL  law-parse: %s\n" m);
  (* output-ref outside a law is a static parse error *)
  (match Parse.parse (mini_spec "    stdout: concat(stdout, \"x\")\n    stderr: \"\"\n    exit: 0") with
   | _ -> incr fails; print_endline "FAIL  law-position: output-ref in an output equation was ACCEPTED"
   | exception Parse.Parse_error _ -> ());
  (match Parse.parse
           ("interface cli \"t\":\n  reads: nothing\ncases on argv:\n  when exit == 0: exit 2 ; stderr: one nonempty line ; stdout: \"\"\n  otherwise: exit 0 ; stderr: \"\" ; stdout: \"\"\nexamples:\n  argv=[] -> exit=2\n") with
   | _ -> incr fails; print_endline "FAIL  law-position: output-ref in a guard was ACCEPTED"
   | exception Parse.Parse_error _ -> ());

  if !fails = 0 then print_endline "ALL OK"
  else (Printf.printf "\n%d FAILURE(S)\n" !fails; exit 1)
