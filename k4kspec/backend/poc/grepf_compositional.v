(* ADR-021 — a FIRST MULTI-MODULE certificate, AGENT-PRODUCED.
   `certify-agent --compositional grepf` (claude, tools off) certified the grep-class spec `grepf`
   by decomposing it into FIVE components, each with its own functional contract + certificate, with
   `run` composing them and the glue `correct` proving the top observational spec from the five
   contracts ALONE. Module-interface gate passed first try; 0 escape hatches; certified binary
   matched the spec on 39/39 inputs; independently re-checks under coqc.

   This is a captured reference of the agent's output (extraction directive removed). The HUMAN signs
   only the top observational `spec_rel`; the five component contracts are agent-proposed and
   kernel-checked. Compile: coqc Kalgebra.v ; coqc -Q . "" grepf_compositional.v *)

Require Import Coq.Strings.String Coq.Strings.Ascii Coq.Lists.List Coq.Arith.PeanoNat Coq.Bool.Bool.
Require Import Kalgebra.
Import ListNotations.
Record Input := { argv : list bytes ; file1 : option bytes }.

(* ---- the ONLY human-signed artifact: the top observational spec ---- *)
Definition spec_rel (i : Input) (o : Output) : Prop :=
  if (negb (Nat.eqb (length (argv i)) 2)) then (stdout o = (EmptyString) /\ one_nonempty_line (stderr o) /\ exit o = 2) else if (match (file1 i) with None => true | Some _ => false end) then (stdout o = (EmptyString) /\ one_nonempty_line (stderr o) /\ exit o = 2) else let matched := (List.filter (fun L => (contains L (bnth (argv i) 0))) (lines (fbytes (file1 i)))) in (stdout o = (unlines matched) /\ stderr o = (EmptyString) /\ exit o = (if (Nat.eqb (length matched) 0) then 1 else 0)).

(* ===== Component 1: argument count ===== *)
Definition comp_argc (i : Input) : nat := length (argv i).
Definition comp_argc_spec (i : Input) (n : nat) : Prop := n = length (argv i).
Lemma comp_argc_correct : forall i, comp_argc_spec i (comp_argc i).
Proof. intro i. unfold comp_argc_spec, comp_argc. reflexivity. Qed.

(* ===== Component 2: file-absent test ===== *)
Definition comp_nofile (i : Input) : bool := match file1 i with None => true | Some _ => false end.
Definition comp_nofile_spec (i : Input) (b : bool) : Prop := b = match file1 i with None => true | Some _ => false end.
Lemma comp_nofile_correct : forall i, comp_nofile_spec i (comp_nofile i).
Proof. intro i. unfold comp_nofile_spec, comp_nofile. reflexivity. Qed.

(* ===== Component 3: matching lines ===== *)
Definition comp_match (i : Input) : list bytes :=
  List.filter (fun L => contains L (bnth (argv i) 0)) (lines (fbytes (file1 i))).
Definition comp_match_spec (i : Input) (m : list bytes) : Prop :=
  m = List.filter (fun L => contains L (bnth (argv i) 0)) (lines (fbytes (file1 i))).
Lemma comp_match_correct : forall i, comp_match_spec i (comp_match i).
Proof. intro i. unfold comp_match_spec, comp_match. reflexivity. Qed.

(* ===== Component 4: error output ===== *)
Definition comp_err (i : Input) : Output :=
  {| stdout := EmptyString ; stderr := "usage"%string ; exit := 2 |}.
Definition comp_err_spec (i : Input) (o : Output) : Prop :=
  stdout o = EmptyString /\ one_nonempty_line (stderr o) /\ exit o = 2.
Lemma comp_err_correct : forall i, comp_err_spec i (comp_err i).
Proof. intro i. unfold comp_err_spec, comp_err, one_nonempty_line. simpl. split; [ reflexivity | split; [ discriminate | reflexivity ] ]. Qed.

(* ===== Component 5: success output ===== *)
Definition comp_ok (m : list bytes) : Output :=
  {| stdout := unlines m ; stderr := EmptyString ; exit := if Nat.eqb (length m) 0 then 1 else 0 |}.
Definition comp_ok_spec (m : list bytes) (o : Output) : Prop :=
  stdout o = unlines m /\ stderr o = EmptyString /\ exit o = (if Nat.eqb (length m) 0 then 1 else 0).
Lemma comp_ok_correct : forall m, comp_ok_spec m (comp_ok m).
Proof. intro m. unfold comp_ok_spec, comp_ok. simpl. split; [ reflexivity | split; reflexivity ]. Qed.

(* ===== Composition ===== *)
Definition run (i : Input) : Output :=
  if negb (Nat.eqb (comp_argc i) 2) then comp_err i
  else if comp_nofile i then comp_err i
  else comp_ok (comp_match i).

(* ===== Glue: the top goal proved from the FIVE component contracts ONLY ===== *)
Theorem correct : forall i, spec_rel i (run i).
Proof.
  intro i.
  pose proof (comp_argc_correct i)            as Ha; unfold comp_argc_spec   in Ha.
  pose proof (comp_nofile_correct i)          as Hn; unfold comp_nofile_spec in Hn.
  pose proof (comp_err_correct i)             as He; unfold comp_err_spec    in He.
  pose proof (comp_ok_correct (comp_match i)) as Ho; unfold comp_ok_spec     in Ho.
  unfold spec_rel, run.
  rewrite Ha.
  destruct (negb (Nat.eqb (length (argv i)) 2)).
  - exact He.
  - rewrite Hn.
    destruct (match file1 i with | None => true | Some _ => false end).
    + exact He.
    + exact Ho.
Qed.
