(* PoC of the k4k certify pipeline for the spec:
     upper ARG  ->  stdout = ascii_upper(ARG) ++ "\n", exit 0 ; wrong arity -> exit 2 *)
Require Import Coq.Strings.String Coq.Strings.Ascii Coq.Lists.List Coq.Arith.PeanoNat.
Import ListNotations.
Open Scope string_scope.

Definition bytes := string.
Record Input  := { argv : list bytes }.
Record Output := { stdout : bytes ; stderr : bytes ; exit : nat }.

(* blessed value algebra: byte-wise ASCII upper-casing (a-z only) *)
Definition up_ascii (c : ascii) : ascii :=
  let n := nat_of_ascii c in
  if andb (Nat.leb 97 n) (Nat.leb n 122) then ascii_of_nat (n - 32) else c.
Fixpoint up (s : string) : string :=
  match s with EmptyString => EmptyString | String c r => String (up_ascii c) (up r) end.

Definition nl : string := String (ascii_of_nat 10) EmptyString.
Definition one_nonempty_line (s : string) : Prop := s <> EmptyString.

(* spec_rel : the relation R denoted by the surface spec *)
Definition spec_rel (i : Input) (o : Output) : Prop :=
  match argv i with
  | [a] => stdout o = up a ++ nl /\ stderr o = EmptyString /\ exit o = 0
  | _   => exit o = 2 /\ one_nonempty_line (stderr o) /\ stdout o = EmptyString
  end.

(* run : the implementation (its stderr message is a concrete choice on the free channel) *)
Definition run (i : Input) : Output :=
  match argv i with
  | [a] => {| stdout := up a ++ nl ; stderr := EmptyString ; exit := 0 |}
  | _   => {| stdout := EmptyString ; stderr := "upper: exactly one argument required" ++ nl ; exit := 2 |}
  end.

(* the machine-checked certificate *)
Theorem correct : forall i, spec_rel i (run i).
Proof.
  intros i. unfold spec_rel, run, one_nonempty_line.
  destruct (argv i) as [| a [| b l]]; cbn; repeat split;
    (reflexivity || discriminate).
Qed.

Require Import Coq.extraction.Extraction.
Require Import Coq.extraction.ExtrOcamlBasic.
Require Import Coq.extraction.ExtrOcamlString.
Require Import Coq.extraction.ExtrOcamlNatInt.
Extraction "upper_ext.ml" run.
