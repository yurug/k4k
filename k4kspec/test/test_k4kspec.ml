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
          List.iter
            (fun (argv, files) ->
              let inp = Eval.input_of argv files in
              let a = (try Some (Eval.run_traced ast inp) with _ -> None) in
              let b = (try Some (Eval.run_traced parsed inp) with _ -> None) in
              if a <> b then
                (incr fails; Printf.printf "FAIL  %s: round-trip behaviour differs on argv=%s\n" file (lst argv)))
            (Check.scenarios ast))
    [ ("grepf.k4kspec", Specs.grepf); ("cutf.k4kspec", Specs.cutf);
      ("catf.k4kspec", Specs.catf); ("kvget.k4kspec", Specs.kvget) ];

  if !fails = 0 then print_endline "ALL OK"
  else (Printf.printf "\n%d FAILURE(S)\n" !fails; exit 1)
