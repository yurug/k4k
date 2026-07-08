(* Worked specs as AST values (parser-free), with author-written examples.
   grepf/cutf/catf mirror spec/k4kspec.md §7. kvget is a NON-CLONE example
   (no standard Unix equivalent) demonstrating reference-free validation. *)

open Ast

let i n = Lit (I n)
let s str = Lit (B str)
let app f xs = App (f, xs)
let len e = app "len" [ e ]
let ne a b = app "ne" [ a; b ]
let eq a b = app "eq" [ a; b ]

(* usage / file error: exit 2, one nonempty stderr line, empty stdout *)
let err2 : (chan * rhs) list =
  [ (Exit, Eq (i 2)); (Stderr, P OneNonemptyLine); (Stdout, Eq (s "")) ]

let case ?guard ?(lets = []) ?(laws = []) outs = { guard; lets; outs; laws }
let ex ?stdout ?exit ?(files = []) argv =
  { ex_argv = argv; ex_files = files; ex_stdout = stdout; ex_exit = exit }

(* ---- grepf NEEDLE FILE ---------------------------------------------------- *)
let grepf : spec =
  {
    name = "grepf"; reads = FileAt 1;
    cases =
      [
        case ~guard:(ne (len ArgvAll) (i 2)) err2;
        case ~guard:(app "absent_footprint" []) err2;
        case
          ~lets:[ ("matched", app "filter" [ app "lines" [ FileBytes ]; Lam ("L", app "contains" [ Var "L"; Argv 0 ]) ]) ]
          [
            (Stdout, Eq (app "unlines" [ Var "matched" ]));
            (Stderr, Eq (s ""));
            (Exit, Eq (If (app "is_empty" [ Var "matched" ], i 1, i 0)));
          ];
      ];
    examples =
      [
        ex ~files:[ ("f", "alpha\nbob\ncab\n") ] ~stdout:"bob\ncab\n" ~exit:0 [ "b"; "f" ];
        ex ~files:[ ("f", "a\nb\n") ] ~stdout:"" ~exit:1 [ "zz"; "f" ];
        ex ~exit:2 [ "x" ];
        ex ~exit:2 [ "x"; "nope" ];
      ];
  }

(* ---- cutf DELIM N FILE ---------------------------------------------------- *)
let cutf : spec =
  {
    name = "cutf"; reads = FileAt 2;
    cases =
      [
        case ~guard:(ne (len ArgvAll) (i 3)) err2;
        case ~guard:(ne (len (Argv 0)) (i 1)) err2;
        case ~guard:(app "not" [ app "is_decimal" [ Argv 1 ] ]) err2;
        case ~guard:(app "lt" [ app "int_of" [ Argv 1 ]; i 1 ]) err2;
        case ~guard:(app "absent_footprint" []) err2;
        case
          ~lets:[ ("n", app "int_of" [ Argv 1 ]) ]
          [
            (Stdout,
             Eq (app "unlines"
                   [ app "map"
                       [ app "lines" [ FileBytes ];
                         Lam ("L", app "get" [ app "split" [ Var "L"; Argv 0 ]; app "sub" [ Var "n"; i 1 ]; s "" ]) ] ]));
            (Stderr, Eq (s ""));
            (Exit, Eq (i 0));
          ];
      ];
    examples =
      [
        ex ~files:[ ("f", "a,b,c\nd,e,f\n") ] ~stdout:"b\ne\n" ~exit:0 [ ","; "2"; "f" ];
        ex ~files:[ ("f", "x,y\n") ] ~stdout:"x\n" ~exit:0 [ ","; "1"; "f" ];
        ex ~files:[ ("f", "a,b\n") ] ~stdout:"\n" ~exit:0 [ ","; "5"; "f" ];   (* missing field -> empty *)
        ex ~exit:2 [ ","; "0"; "f" ];
        ex ~exit:2 [ "ab"; "1"; "f" ];
        ex ~exit:2 [ ","; "q"; "f" ];
        ex ~exit:2 [ ","; "1" ];
        ex ~exit:2 [ ","; "1"; "missing" ];   (* valid args, absent file -> exercises case #4 *)
      ];
  }

(* ---- catf FILE... --------------------------------------------------------- *)
let catf : spec =
  {
    name = "catf"; reads = FileAtEach;
    cases =
      [
        case ~guard:(eq (len ArgvAll) (i 0)) err2;
        case ~guard:(app "any" [ ArgvAll; Lam ("a", app "absent" [ app "file_at" [ Var "a" ] ]) ]) err2;
        case
          [
            (Stdout,
             Eq (app "fold"
                   [ ArgvAll; s "";
                     Lam ("acc", Lam ("a", app "concat" [ Var "acc"; app "opt_bytes" [ app "file_at" [ Var "a" ] ] ])) ]));
            (Stderr, Eq (s ""));
            (Exit, Eq (i 0));
          ];
      ];
    examples =
      [
        ex ~files:[ ("f1", "a\n"); ("f2", "b\n") ] ~stdout:"a\nb\n" ~exit:0 [ "f1"; "f2" ];
        ex ~exit:2 [];
        ex ~files:[ ("f1", "a\n") ] ~exit:2 [ "f1"; "missing" ];
      ];
  }

(* ---- kvget KEY FILE  (NON-CLONE: print value of first "key=value" line) ---- *)
(* value = the field after the FIRST '='; not-found is exit 1 (silent, not an error). *)
let kvget : spec =
  let keyeq = Lam ("L", eq (app "get" [ app "split" [ Var "L"; s "=" ]; i 0; s "" ]) (Argv 0)) in
  {
    name = "kvget"; reads = FileAt 1;
    cases =
      [
        case ~guard:(ne (len ArgvAll) (i 2)) err2;
        case ~guard:(app "absent_footprint" []) err2;
        case
          ~lets:
            [
              ("found", app "any" [ app "lines" [ FileBytes ]; keyeq ]);
              ("line", app "first" [ app "lines" [ FileBytes ]; keyeq; s "" ]);
              ("val", app "get" [ app "split" [ Var "line"; s "=" ]; i 1; s "" ]);
            ]
          [
            (Stdout, Eq (If (Var "found", app "concat" [ Var "val"; s "\n" ], s "")));
            (Stderr, Eq (s ""));
            (Exit, Eq (If (Var "found", i 0, i 1)));
          ];
      ];
    examples =
      [
        ex ~files:[ ("f", "a=1\nk=2\nb=3\n") ] ~stdout:"2\n" ~exit:0 [ "k"; "f" ];
        ex ~files:[ ("f", "a=1\n") ] ~stdout:"" ~exit:1 [ "zzz"; "f" ];
        ex ~exit:2 [ "k" ];
        ex ~exit:2 [ "k"; "missing" ];
      ];
  }

(* ---- bsort ARG  (RELATIONAL: under-determined output, constrained by a sort LAW) ---------- *)
(* stdout's bytes are a SORTED PERMUTATION of ARG's bytes. The output is NOT pinned — only the
   law constrains it — so the deterministic generator cannot do it; only the agent-proof path
   (agent chooses a sort + proves Sorted/Permutation by induction) can. The genuine hard-proof test. *)
let bsort : spec =
  {
    name = "bsort"; reads = NoFiles;
    cases =
      [
        case ~guard:(ne (len ArgvAll) (i 1)) err2;
        case
          ~laws:
            [ App ("sorted", [ App ("list_of", [ OStdout ]) ]);
              App ("permutation", [ App ("list_of", [ OStdout ]); App ("list_of", [ Argv 0 ]) ]) ]
          [ (Stdout, P Any); (Stderr, Eq (s "")); (Exit, Eq (i 0)) ];
      ];
    examples = [ ex ~exit:2 []; ex ~exit:2 [ "a"; "b" ] ];   (* success path is under-determined *)
  }

(* ---- partition ARG  (RELATIONAL, NON-SORT: a custom-preorder proof obligation) ------------- *)
(* stdout is a PERMUTATION of ARG's bytes, PARTITIONED around 'm' (109): every byte < 'm' precedes
   every byte >= 'm'. "partitioned" = `Sorted part_le` for the implication-preorder part_le (in
   Kalgebra). The agent cannot reuse a stdlib byte order — it must discover that part_le is a
   transitive total preorder and prove its chosen impl correct against it. Not the sort canon. *)
let partition : spec =
  {
    name = "partition"; reads = NoFiles;
    cases =
      [
        case ~guard:(ne (len ArgvAll) (i 1)) err2;
        case
          ~laws:
            [ App ("partitioned", [ App ("list_of", [ OStdout ]) ]);
              App ("permutation", [ App ("list_of", [ OStdout ]); App ("list_of", [ Argv 0 ]) ]) ]
          [ (Stdout, P Any); (Stderr, Eq (s "")); (Exit, Eq (i 0)) ];
      ];
    examples = [ ex ~exit:2 []; ex ~exit:2 [ "a"; "b" ] ];   (* success path is under-determined *)
  }

(* ---- usort ARG  (ADVERSARIAL: TWO interacting invariants — strict sort + set equality) ------ *)
(* stdout's bytes are ARG's bytes SORTED and DEDUPLICATED. Expressed as: `Sorted ascii_lt` (a STRICT
   order, so the output has no duplicates) AND `same_set` (same membership as ARG). The agent must
   produce a sort+dedup and prove BOTH a strict-sortedness invariant (each consecutive pair strictly
   increases — needs the dedup to kill equals) AND set-preservation in both directions. Harder than
   partition: two different invariants that interact, NoDup-flavoured. The ceiling probe. *)
let usort : spec =
  {
    name = "usort"; reads = NoFiles;
    cases =
      [
        case ~guard:(ne (len ArgvAll) (i 1)) err2;
        case
          ~laws:
            [ App ("sorted_strict", [ App ("list_of", [ OStdout ]) ]);
              App ("same_set", [ App ("list_of", [ OStdout ]); App ("list_of", [ Argv 0 ]) ]) ]
          [ (Stdout, P Any); (Stderr, Eq (s "")); (Exit, Eq (i 0)) ];
      ];
    examples = [ ex ~exit:2 []; ex ~exit:2 [ "a"; "b" ] ];   (* success path is under-determined *)
  }

let all = [ grepf; cutf; catf; kvget; bsort; partition; usort ]
let by_name = List.map (fun s -> (s.name, s)) all
