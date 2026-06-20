(* Elaborator: Ast.spec -> a self-contained Rocq .v whose [correct] theorem, once
   checked by coqc, certifies that the extracted [run] satisfies [spec_rel] (the relation
   R denoted by the surface spec). Covers the NO-FILE and single-FILE (FileAt) fragments;
   FileAtEach (variadic) is M4. The generated .v matches backend/poc/upper.v's guarantees. *)

open Ast

(* The blessed value algebra in Rocq — the certified vocabulary (audited once).
   These defs MUST match lib/algebra.ml. Output record is fixed; Input is footprint-specific. *)
let preamble =
  {coq|Require Import Coq.Strings.String Coq.Strings.Ascii Coq.Lists.List Coq.Arith.PeanoNat Coq.Bool.Bool.
Import ListNotations.

Definition bytes := string.
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

Definition nlc : ascii := ascii_of_nat 10.
Definition bnth (l : list bytes) (n : nat) : bytes := nth n l EmptyString.
Definition fbytes (o : option bytes) : bytes := match o with Some c => c | None => EmptyString end.
Definition one_nonempty_line (s : string) : Prop := s <> EmptyString.

(* split on a single char, mechanical (keeps every piece, incl. a trailing empty) *)
Fixpoint splitc (d : ascii) (s : string) : list string :=
  match s with
  | EmptyString => EmptyString :: nil
  | String c r =>
      if Ascii.eqb c d then EmptyString :: splitc d r
      else match splitc d r with nil => String c EmptyString :: nil | h :: t => String c h :: t end
  end.
Definition hchar (s : string) : ascii := match s with String c _ => c | EmptyString => ascii_of_nat 0 end.
Definition splits (delim s : string) : list string := splitc (hchar delim) s.   (* delim is 1 byte (guarded) *)
Definition drop_last_empty (l : list string) : list string :=
  match rev l with EmptyString :: t => rev t | _ => l end.
(* POSIX lines: a final '\n' is a terminator, not an empty trailing line *)
Definition lines (b : string) : list string :=
  match b with EmptyString => nil | _ => drop_last_empty (splitc nlc b) end.
Definition lfirst (p : string -> bool) (l : list string) (d : string) : string :=
  match find p l with Some v => v | None => d end.
Fixpoint unlines (l : list string) : string :=
  match l with nil => EmptyString | x :: r => append x (String nlc (unlines r)) end.

Fixpoint is_prefix (p s : string) : bool :=
  match p with
  | EmptyString => true
  | String pc pr => match s with EmptyString => false | String sc sr => if Ascii.eqb pc sc then is_prefix pr sr else false end
  end.
Fixpoint contains (s needle : string) : bool :=
  match s with EmptyString => is_prefix needle EmptyString | String c r => if is_prefix needle (String c r) then true else contains r needle end.

Definition is_digit (c : ascii) : bool := andb (Nat.leb 48 (nat_of_ascii c)) (Nat.leb (nat_of_ascii c) 57).
Fixpoint all_digits (s : string) : bool := match s with EmptyString => true | String c r => andb (is_digit c) (all_digits r) end.
Definition is_decimal (s : string) : bool := andb (negb (String.eqb s EmptyString)) (all_digits s).
Fixpoint natstr (s : string) (acc : nat) : nat := match s with EmptyString => acc | String c r => natstr r (acc * 10 + (nat_of_ascii c - 48)) end.
Definition int_of (s : string) : nat := if is_decimal s then natstr s 0 else 0.
|coq}

let input_record = function
  | NoFiles -> "Record Input := { argv : list bytes }."
  | FileAt _ -> "Record Input := { argv : list bytes ; file1 : option bytes }."
  | FileAtEach -> "Record Input := { argv : list bytes ; contents : list (option bytes) }."

(* ---- expression translation (env tracks let/lambda variable types) -------- *)
type ty = TList | TBytes | TInt | TBool

type env = (string * ty) list

let rec typ (env : env) (e : expr) : ty =
  match e with
  | Lit (B _) -> TBytes | Lit (I _) -> TInt | Lit (Bool _) -> TBool | Lit _ -> TBytes
  | Argv _ | Stdin | FileBytes -> TBytes
  | ArgvAll -> TList
  | If (_, a, _) -> typ env a
  | Var x -> (try List.assoc x env with Not_found -> TBytes)
  | Lam _ -> TBytes
  | App (f, _) ->
      (match f with
       | "len" | "int_of" | "sub" | "add" | "count" -> TInt
       | "concat" | "ascii_upper" | "ascii_lower" | "get" | "head" | "first" | "join" | "unlines" | "opt_bytes" | "replace" -> TBytes
       | "split" | "lines" | "filter" | "map" -> TList
       | _ -> TBool)

let coq_string (s : string) : string =
  let b = Buffer.create (String.length s * 8 + 8) in
  Buffer.add_char b '(';
  String.iter (fun c -> Buffer.add_string b (Printf.sprintf "String (ascii_of_nat %d) (" (Char.code c))) s;
  Buffer.add_string b "EmptyString";
  String.iter (fun _ -> Buffer.add_char b ')') s;
  Buffer.add_char b ')';
  Buffer.contents b

let fail_unsupported f = failwith (Printf.sprintf "rocq_emit: unsupported construct: %s" f)

(* the spec's footprint, set by [emit]; the variadic (FileAtEach) case rewrites
   combinators over `argv` to iterate over the pre-read `contents` list instead. *)
let cur_reads = ref NoFiles

let rec re (env : env) (e : expr) : string =
  match e with
  | Lit (B s) -> coq_string s
  | Lit (I n) -> string_of_int n
  | Lit (Bool b) -> if b then "true" else "false"
  | Lit _ -> fail_unsupported "lit"
  | Argv k -> Printf.sprintf "(bnth (argv i) %d)" k
  | ArgvAll -> "(argv i)"
  | Stdin -> fail_unsupported "stdin"
  | FileBytes -> "(fbytes (file1 i))"
  | Var x -> x
  | If (c, a, b) -> Printf.sprintf "(if %s then %s else %s)" (re env c) (re env a) (re env b)
  | Lam (x, body) -> Printf.sprintf "(fun %s => %s)" x (re ((x, TBytes) :: env) body)
  | App (f, args) -> re_app env f args

(* the list a combinator iterates: for FileAtEach, `argv` becomes the pre-read `contents`
   (the lambda variable then ranges over `option bytes`, and `file_at x` is the identity). *)
and re_list env l = if l = ArgvAll && !cur_reads = FileAtEach then "(contents i)" else re env l

(* combinator whose 2nd argument is a predicate/mapping lambda over the element type *)
and re_lam_combinator env coqf l lam =
  match lam with
  | Lam (x, body) -> Printf.sprintf "(%s (fun %s => %s) %s)" coqf x (re ((x, TBytes) :: env) body) (re_list env l)
  | _ -> fail_unsupported "combinator needs a lambda"

and re_app env f args =
  match f, args with
  | "len", [ e ] -> (match typ env e with TList -> Printf.sprintf "(length %s)" (re env e) | _ -> Printf.sprintf "(String.length %s)" (re env e))
  | "concat", [ a; b ] -> Printf.sprintf "(append %s %s)" (re env a) (re env b)
  | "ascii_upper", [ e ] -> Printf.sprintf "(ascii_upper %s)" (re env e)
  | "ascii_lower", [ e ] -> Printf.sprintf "(ascii_lower %s)" (re env e)
  | "lines", [ e ] -> Printf.sprintf "(lines %s)" (re env e)
  | "unlines", [ e ] -> Printf.sprintf "(unlines %s)" (re env e)
  | "contains", [ a; b ] -> Printf.sprintf "(contains %s %s)" (re env a) (re env b)
  | "filter", [ l; lam ] -> re_lam_combinator env "List.filter" l lam
  | "map", [ l; lam ] -> re_lam_combinator env "List.map" l lam
  | "split", [ s; sep ] -> Printf.sprintf "(splits %s %s)" (re env sep) (re env s)
  | "get", [ l; i; d ] -> Printf.sprintf "(nth %s %s %s)" (re env i) (re env l) (re env d)
  | "any", [ l; Lam (x, body) ] -> Printf.sprintf "(existsb (fun %s => %s) %s)" x (re ((x, TBytes) :: env) body) (re_list env l)
  | "all", [ l; Lam (x, body) ] -> Printf.sprintf "(forallb (fun %s => %s) %s)" x (re ((x, TBytes) :: env) body) (re_list env l)
  | "first", [ l; Lam (x, body); d ] -> Printf.sprintf "(lfirst (fun %s => %s) %s %s)" x (re ((x, TBytes) :: env) body) (re_list env l) (re env d)
  | "count", [ l; Lam (x, body) ] -> Printf.sprintf "(length (List.filter (fun %s => %s) %s))" x (re ((x, TBytes) :: env) body) (re_list env l)
  | "fold", [ l; init; Lam (acc, Lam (x, body)) ] ->
      Printf.sprintf "(fold_left (fun %s %s => %s) %s %s)" acc x (re ((x, TBytes) :: (acc, TBytes) :: env) body) (re_list env l) (re env init)
  | "file_at", [ e ] -> re env e                                    (* under FileAtEach iteration, the var IS the content option *)
  | "opt_bytes", [ e ] -> Printf.sprintf "(fbytes %s)" (re env e)
  | "absent", [ e ] -> Printf.sprintf "(match %s with None => true | Some _ => false end)" (re env e)
  | "present", [ e ] -> Printf.sprintf "(match %s with None => false | Some _ => true end)" (re env e)
  | "eq", [ a; b ] ->
      (match typ env a with
       | TInt -> Printf.sprintf "(Nat.eqb %s %s)" (re env a) (re env b)
       | TBytes -> Printf.sprintf "(String.eqb %s %s)" (re env a) (re env b)
       | TBool -> Printf.sprintf "(Bool.eqb %s %s)" (re env a) (re env b)
       | TList -> fail_unsupported "list-eq")
  | "ne", [ a; b ] -> Printf.sprintf "(negb %s)" (re_app env "eq" [ a; b ])
  | "lt", [ a; b ] -> Printf.sprintf "(Nat.ltb %s %s)" (re env a) (re env b)
  | "le", [ a; b ] -> Printf.sprintf "(Nat.leb %s %s)" (re env a) (re env b)
  | "gt", [ a; b ] -> Printf.sprintf "(Nat.ltb %s %s)" (re env b) (re env a)
  | "ge", [ a; b ] -> Printf.sprintf "(Nat.leb %s %s)" (re env b) (re env a)
  | "not", [ e ] -> Printf.sprintf "(negb %s)" (re env e)
  | "and", [ a; b ] -> Printf.sprintf "(andb %s %s)" (re env a) (re env b)
  | "or", [ a; b ] -> Printf.sprintf "(orb %s %s)" (re env a) (re env b)
  | "is_empty", [ e ] -> (match typ env e with TList -> Printf.sprintf "(Nat.eqb (length %s) 0)" (re env e) | _ -> Printf.sprintf "(String.eqb %s EmptyString)" (re env e))
  | "sub", [ a; b ] -> Printf.sprintf "(%s - %s)" (re env a) (re env b)
  | "add", [ a; b ] -> Printf.sprintf "(%s + %s)" (re env a) (re env b)
  | "is_decimal", [ e ] -> Printf.sprintf "(is_decimal %s)" (re env e)
  | "int_of", [ e ] -> Printf.sprintf "(int_of %s)" (re env e)
  | "absent_footprint", [] -> "(match (file1 i) with None => true | Some _ => false end)"
  | "present_footprint", [] -> "(match (file1 i) with None => false | Some _ => true end)"
  | _ -> fail_unsupported f

(* ---- per-case bodies ------------------------------------------------------ *)
let stderr_prop env = function
  | Eq e -> Printf.sprintf "stderr o = %s" (re env e)
  | P OneNonemptyLine -> "one_nonempty_line (stderr o)"
  | P Nonempty -> "stderr o <> EmptyString"
  | P EmptyB -> "stderr o = EmptyString"
  | P Any -> "True"

let outc ch (c : case) = List.assoc ch c.outs

(* emit the case's let-bindings, threading the type env, then call [body] with it *)
let emit_lets (c : case) (body : env -> string) : string =
  let rec go env = function
    | [] -> body env
    | (x, e) :: rest -> Printf.sprintf "let %s := %s in %s" x (re env e) (go ((x, typ env e) :: env) rest)
  in
  go [] c.lets

let case_prop (c : case) : string =
  emit_lets c (fun env ->
      let stdout_e = match outc Stdout c with Eq e -> re env e | P _ -> failwith "stdout must be pinned" in
      let exit_e = match outc Exit c with Eq e -> re env e | P _ -> failwith "exit must be pinned" in
      Printf.sprintf "(stdout o = %s /\\ %s /\\ exit o = %s)" stdout_e (stderr_prop env (outc Stderr c)) exit_e)

let case_run (name : string) (c : case) : string =
  emit_lets c (fun env ->
      let stdout_e = match outc Stdout c with Eq e -> re env e | P _ -> "EmptyString" in
      let exit_e = match outc Exit c with Eq e -> re env e | P _ -> "0" in
      let stderr_e =
        match outc Stderr c with
        | Eq e -> re env e
        | P (OneNonemptyLine | Nonempty) -> coq_string (name ^ ": error")
        | P (Any | EmptyB) -> "EmptyString"
      in
      Printf.sprintf "{| stdout := %s; stderr := %s; exit := %s |}" stdout_e stderr_e exit_e)

let rec chain body = function
  | [ c ] -> body c
  | c :: rest -> (match c.guard with Some g -> Printf.sprintf "if %s then %s else %s" (re [] g) (body c) (chain body rest) | None -> body c)
  | [] -> failwith "rocq_emit: no cases"

let proof reads =
  let pre = match reads with FileAt _ -> "destruct (file1 i); cbn; " | FileAtEach -> "" | NoFiles -> "" in
  Printf.sprintf
    "Theorem correct : forall i, spec_rel i (run i).\n\
    \  Proof.\n\
    \    intros i. unfold spec_rel, run, one_nonempty_line, fbytes.\n\
    \    %srepeat (match goal with |- context [ if ?b then _ else _ ] => destruct b end);\n\
    \    cbn; repeat split; (reflexivity || discriminate || exact I).\n\
    \  Qed.\n" pre

let extraction name =
  Printf.sprintf
    "Require Import Coq.extraction.Extraction.\n\
     Require Import Coq.extraction.ExtrOcamlBasic.\n\
     Require Import Coq.extraction.ExtrOcamlString.\n\
     Require Import Coq.extraction.ExtrOcamlNatInt.\n\
     Extraction \"%s_ext.ml\" run.\n" name

let emit (sp : spec) : string =
  cur_reads := sp.reads;
  String.concat "\n"
    [ preamble;
      input_record sp.reads;
      Printf.sprintf "Definition spec_rel (i : Input) (o : Output) : Prop :=\n  %s." (chain case_prop sp.cases);
      Printf.sprintf "Definition run (i : Input) : Output :=\n  %s." (chain (case_run sp.name) sp.cases);
      proof sp.reads;
      extraction sp.name ]
