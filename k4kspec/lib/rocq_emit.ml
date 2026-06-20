(* Elaborator: Ast.spec -> a self-contained Rocq .v source whose [correct] theorem,
   once checked by coqc, certifies that the extracted [run] satisfies the relation
   [spec_rel] denoted by the surface spec. v1 covers the NO-FILE fragment (footprint
   NoFiles); file footprints raise (M3). The generated .v matches backend/poc/upper.v. *)

open Ast

(* the blessed value algebra in Rocq — the certified vocabulary (audited once). *)
let preamble =
  {coq|Require Import Coq.Strings.String Coq.Strings.Ascii Coq.Lists.List Coq.Arith.PeanoNat Coq.Bool.Bool.
Import ListNotations.

Definition bytes := string.
Record Input  := { argv : list bytes }.
Record Output := { stdout : bytes ; stderr : bytes ; exit : nat }.

Definition up_ascii (c : ascii) : ascii :=
  let n := nat_of_ascii c in
  if andb (Nat.leb 97 n) (Nat.leb n 122) then ascii_of_nat (n - 32) else c.
Fixpoint ascii_upper (s : string) : string :=
  match s with EmptyString => EmptyString | String c r => String (up_ascii c) (ascii_upper r) end.
Definition lo_ascii (c : ascii) : ascii :=
  let n := nat_of_ascii c in
  if andb (Nat.leb 65 n) (Nat.leb n 90) then ascii_of_nat (n + 32) else c.
Fixpoint ascii_lower (s : string) : string :=
  match s with EmptyString => EmptyString | String c r => String (lo_ascii c) (ascii_lower r) end.

Definition bnth (l : list bytes) (n : nat) : bytes := nth n l EmptyString.
Definition one_nonempty_line (s : string) : Prop := s <> EmptyString.
|coq}

(* ---- expression translation ---------------------------------------------- *)
type ty = TList | TBytes | TInt | TBool

let rec typ (e : expr) : ty =
  match e with
  | Lit (B _) -> TBytes | Lit (I _) -> TInt | Lit (Bool _) -> TBool | Lit _ -> TBytes
  | Argv _ | Stdin | FileBytes -> TBytes
  | ArgvAll -> TList
  | If (_, a, _) -> typ a
  | Var _ -> TBytes
  | Lam _ -> TBytes
  | App (f, _) ->
      (match f with
       | "len" | "int_of" | "sub" | "add" | "count" -> TInt
       | "concat" | "ascii_upper" | "ascii_lower" | "get" | "head" | "first" | "join" | "unlines" | "opt_bytes" | "replace" -> TBytes
       | "split" | "lines" | "filter" | "map" -> TList
       | _ -> TBool)

(* a Coq [string] literal built from bytes (robust to newlines / non-printables) *)
let coq_string (s : string) : string =
  let b = Buffer.create (String.length s * 8 + 8) in
  Buffer.add_char b '(';
  String.iter (fun c -> Buffer.add_string b (Printf.sprintf "String (ascii_of_nat %d) (" (Char.code c))) s;
  Buffer.add_string b "EmptyString";
  String.iter (fun _ -> Buffer.add_char b ')') s;
  Buffer.add_char b ')';
  Buffer.contents b

let fail_unsupported f = failwith (Printf.sprintf "rocq_emit: unsupported in the no-file fragment: %s" f)

let rec re (e : expr) : string =
  match e with
  | Lit (B s) -> coq_string s
  | Lit (I n) -> string_of_int n
  | Lit (Bool b) -> if b then "true" else "false"
  | Lit _ -> fail_unsupported "lit"
  | Argv k -> Printf.sprintf "(bnth (argv i) %d)" k
  | ArgvAll -> "(argv i)"
  | Stdin -> fail_unsupported "stdin"
  | FileBytes -> fail_unsupported "file.bytes"
  | Var x -> x
  | If (c, a, b) -> Printf.sprintf "(if %s then %s else %s)" (re c) (re a) (re b)
  | Lam _ -> fail_unsupported "lambda"
  | App (f, args) -> re_app f args

and re_app f args =
  match f, args with
  | "len", [ e ] -> (match typ e with TList -> Printf.sprintf "(length %s)" (re e) | _ -> Printf.sprintf "(String.length %s)" (re e))
  | "concat", [ a; b ] -> Printf.sprintf "(append %s %s)" (re a) (re b)
  | "ascii_upper", [ e ] -> Printf.sprintf "(ascii_upper %s)" (re e)
  | "ascii_lower", [ e ] -> Printf.sprintf "(ascii_lower %s)" (re e)
  | "eq", [ a; b ] ->
      (match typ a with
       | TInt -> Printf.sprintf "(Nat.eqb %s %s)" (re a) (re b)
       | TBytes -> Printf.sprintf "(String.eqb %s %s)" (re a) (re b)
       | TBool -> Printf.sprintf "(Bool.eqb %s %s)" (re a) (re b)
       | TList -> fail_unsupported "list-eq")
  | "ne", [ a; b ] -> Printf.sprintf "(negb %s)" (re_app "eq" [ a; b ])
  | "lt", [ a; b ] -> Printf.sprintf "(Nat.ltb %s %s)" (re a) (re b)
  | "le", [ a; b ] -> Printf.sprintf "(Nat.leb %s %s)" (re a) (re b)
  | "gt", [ a; b ] -> Printf.sprintf "(Nat.ltb %s %s)" (re b) (re a)
  | "ge", [ a; b ] -> Printf.sprintf "(Nat.leb %s %s)" (re b) (re a)
  | "not", [ e ] -> Printf.sprintf "(negb %s)" (re e)
  | "and", [ a; b ] -> Printf.sprintf "(andb %s %s)" (re a) (re b)
  | "or", [ a; b ] -> Printf.sprintf "(orb %s %s)" (re a) (re b)
  | "is_empty", [ e ] -> (match typ e with TList -> Printf.sprintf "(Nat.eqb (length %s) 0)" (re e) | _ -> Printf.sprintf "(String.eqb %s EmptyString)" (re e))
  | "sub", [ a; b ] -> Printf.sprintf "(%s - %s)" (re a) (re b)
  | "add", [ a; b ] -> Printf.sprintf "(%s + %s)" (re a) (re b)
  | _ -> fail_unsupported f

(* ---- per-case bodies ------------------------------------------------------ *)
let stderr_prop = function
  | Eq e -> Printf.sprintf "stderr o = %s" (re e)
  | P OneNonemptyLine -> "one_nonempty_line (stderr o)"
  | P Nonempty -> "stderr o <> EmptyString"
  | P EmptyB -> "stderr o = EmptyString"
  | P Any -> "True"

let outc ch (c : case) = List.assoc ch c.outs

let with_lets (c : case) body =
  List.fold_right (fun (x, e) acc -> Printf.sprintf "let %s := %s in %s" x (re e) acc) c.lets body

let case_prop (c : case) : string =
  let stdout_e = match outc Stdout c with Eq e -> re e | P _ -> failwith "stdout must be pinned" in
  let exit_e = match outc Exit c with Eq e -> re e | P _ -> failwith "exit must be pinned" in
  with_lets c (Printf.sprintf "(stdout o = %s /\\ %s /\\ exit o = %s)" stdout_e (stderr_prop (outc Stderr c)) exit_e)

let case_run (name : string) (c : case) : string =
  let stdout_e = match outc Stdout c with Eq e -> re e | P _ -> "EmptyString" in
  let exit_e = match outc Exit c with Eq e -> re e | P _ -> "0" in
  let stderr_e =
    match outc Stderr c with
    | Eq e -> re e
    | P (OneNonemptyLine | Nonempty) -> coq_string (name ^ ": error")
    | P (Any | EmptyB) -> "EmptyString"
  in
  with_lets c (Printf.sprintf "{| stdout := %s; stderr := %s; exit := %s |}" stdout_e stderr_e exit_e)

let rec chain body = function
  | [ c ] -> body c
  | c :: rest -> (match c.guard with Some g -> Printf.sprintf "if %s then %s else %s" (re g) (body c) (chain body rest) | None -> body c)
  | [] -> failwith "rocq_emit: no cases"

let proof =
  "Theorem correct : forall i, spec_rel i (run i).\n\
  \  Proof.\n\
  \    intros i. unfold spec_rel, run, one_nonempty_line.\n\
  \    repeat (match goal with |- context [ if ?b then _ else _ ] => destruct b end);\n\
  \    cbn; repeat split; (reflexivity || discriminate || exact I).\n\
  \  Qed.\n"

let extraction name =
  Printf.sprintf
    "Require Import Coq.extraction.Extraction.\n\
     Require Import Coq.extraction.ExtrOcamlBasic.\n\
     Require Import Coq.extraction.ExtrOcamlString.\n\
     Require Import Coq.extraction.ExtrOcamlNatInt.\n\
     Extraction \"%s_ext.ml\" run.\n" name

let emit (sp : spec) : string =
  (match sp.reads with NoFiles -> () | _ -> failwith "rocq_emit: file footprints not yet supported (M3)");
  String.concat "\n"
    [ preamble;
      Printf.sprintf "Definition spec_rel (i : Input) (o : Output) : Prop :=\n  %s." (chain case_prop sp.cases);
      Printf.sprintf "Definition run (i : Input) : Output :=\n  %s." (chain (case_run sp.name) sp.cases);
      proof;
      extraction sp.name ]
