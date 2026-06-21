(* ADR-021 prototype — COMPOSITIONAL certification.
   A program whose `run = format ∘ core` is certified from TWO component contracts:
     - core   : list ascii -> list ascii   (a sort)            contract: Sorted /\ Permutation
     - format : list ascii -> string       (render to bytes)   contract: list_of (format l) = l
   The top spec (sorted permutation, at the byte level) is proved by the GLUE, which uses ONLY the
   two component certificates. Then `AbstractComposition` is the MODULE-INTERFACE GATE: the SAME
   glue goes through with the components UNINTERPRETED and their contracts as hypotheses — i.e. the
   top proof composes from the contracts BEFORE any component is implemented or proved.
   Compile: coqc Kalgebra.v ; coqc -Q . "" compose_sort.v *)

Require Import Coq.Strings.String Coq.Strings.Ascii Coq.Lists.List Coq.Arith.PeanoNat Coq.Bool.Bool.
Require Import Kalgebra.
Import ListNotations.

(* ---- a verified insertion sort (the core's internal development) ---------------------------- *)
Definition leb_ascii (a b : ascii) : bool := Nat.leb (nat_of_ascii a) (nat_of_ascii b).

Fixpoint insert_ascii (x : ascii) (l : list ascii) : list ascii :=
  match l with
  | nil => cons x nil
  | cons h t => if leb_ascii x h then cons x (cons h t) else cons h (insert_ascii x t)
  end.
Fixpoint isort_ascii (l : list ascii) : list ascii :=
  match l with nil => nil | cons h t => insert_ascii h (isort_ascii t) end.

Lemma leb_ascii_true : forall a b, leb_ascii a b = true -> ascii_le a b.
Proof. intros a b H. unfold ascii_le. unfold leb_ascii in H. apply Nat.leb_le in H. exact H. Qed.
Lemma leb_ascii_false : forall a b, leb_ascii a b = false -> ascii_le b a.
Proof. intros a b H. unfold ascii_le. unfold leb_ascii in H. apply Nat.leb_gt in H. apply Nat.lt_le_incl. exact H. Qed.

Lemma insert_perm : forall x l, Permutation (insert_ascii x l) (cons x l).
Proof.
  intros x l. induction l as [|h t IH]; cbn [insert_ascii].
  { apply Permutation_refl. }
  { destruct (leb_ascii x h) eqn:Hb.
    { apply Permutation_refl. }
    { apply Permutation_trans with (cons h (cons x t)).
      { apply perm_skip. exact IH. } { apply perm_swap. } } }
Qed.
Lemma isort_perm : forall l, Permutation (isort_ascii l) l.
Proof.
  intros l. induction l as [|h t IH]; cbn [isort_ascii].
  { apply Permutation_refl. }
  { apply Permutation_trans with (cons h (isort_ascii t)).
    { apply insert_perm. } { apply perm_skip. exact IH. } }
Qed.
Lemma HdRel_insert : forall a x t, ascii_le a x -> HdRel ascii_le a t -> HdRel ascii_le a (insert_ascii x t).
Proof.
  intros a x t Hax Ht. destruct t as [|h u]; cbn [insert_ascii].
  { apply HdRel_cons. exact Hax. }
  { destruct (leb_ascii x h) eqn:Hb.
    { apply HdRel_cons. exact Hax. }
    { apply HdRel_cons. inversion Ht; subst. assumption. } }
Qed.
Lemma insert_sorted : forall x l, Sorted ascii_le l -> Sorted ascii_le (insert_ascii x l).
Proof.
  intros x l. induction l as [|h t IH]; intro Hl; cbn [insert_ascii].
  { apply Sorted_cons. apply Sorted_nil. apply HdRel_nil. }
  { apply Sorted_inv in Hl. destruct Hl as [Ht Hhd].
    destruct (leb_ascii x h) eqn:Hb.
    { apply Sorted_cons. { apply Sorted_cons. exact Ht. exact Hhd. } { apply HdRel_cons. apply leb_ascii_true. exact Hb. } }
    { apply Sorted_cons. { apply IH. exact Ht. } { apply HdRel_insert. apply leb_ascii_false. exact Hb. exact Hhd. } } }
Qed.
Lemma isort_sorted : forall l, Sorted ascii_le (isort_ascii l).
Proof. intros l. induction l as [|h t IH]; cbn [isort_ascii]. { apply Sorted_nil. } { apply insert_sorted. exact IH. } Qed.

(* ============================ COMPONENT 1 — core (sort) ============================ *)
Definition core (l : list ascii) : list ascii := isort_ascii l.
Definition core_spec (l l' : list ascii) : Prop := Sorted ascii_le l' /\ Permutation l' l.
Lemma core_correct : forall l, core_spec l (core l).
Proof. intro l. unfold core, core_spec. split. apply isort_sorted. apply isort_perm. Qed.

(* ============================ COMPONENT 2 — format (render) ============================ *)
Definition format (l : list ascii) : string := string_of_list_ascii l.
Definition format_spec (l : list ascii) (s : string) : Prop := list_ascii_of_string s = l.
Lemma format_correct : forall l, format_spec l (format l).
Proof. intro l. unfold format, format_spec. apply list_ascii_of_string_of_list_ascii. Qed.

(* ============================ COMPOSITION ============================ *)
Definition run (arg : string) : string := format (core (list_ascii_of_string arg)).

(* the top, byte-level observational spec (what a human would sign) *)
Definition top_spec (arg out : string) : Prop :=
  Sorted ascii_le (list_ascii_of_string out) /\
  Permutation (list_ascii_of_string out) (list_ascii_of_string arg).

(* the GLUE: derive the top spec from the two component certificates ONLY *)
Theorem compose : forall arg, top_spec arg (run arg).
Proof.
  intro arg. unfold top_spec, run.
  pose proof (format_correct (core (list_ascii_of_string arg))) as Hf. unfold format_spec in Hf.
  pose proof (core_correct (list_ascii_of_string arg)) as Hc. unfold core_spec in Hc.
  rewrite Hf. destruct Hc as [Hs Hp]. split; [ exact Hs | exact Hp ].
Qed.

(* ===== MODULE-INTERFACE GATE: the glue composes from CONTRACTS ALONE (components abstract) ===== *)
Section AbstractComposition.
  Variable acore   : list ascii -> list ascii.
  Variable aformat : list ascii -> string.
  Hypothesis acore_correct   : forall l, Sorted ascii_le (acore l) /\ Permutation (acore l) l.
  Hypothesis aformat_correct : forall l, list_ascii_of_string (aformat l) = l.

  Definition arun (arg : string) : string := aformat (acore (list_ascii_of_string arg)).

  (* coqc accepts this with acore/aformat UNINTERPRETED — the top proof goes through given only the
     contracts, i.e. the decomposition is valid BEFORE either component is built. *)
  Theorem acompose : forall arg,
    Sorted ascii_le (list_ascii_of_string (arun arg)) /\
    Permutation (list_ascii_of_string (arun arg)) (list_ascii_of_string arg).
  Proof.
    intro arg. unfold arun.
    rewrite (aformat_correct (acore (list_ascii_of_string arg))).
    exact (acore_correct (list_ascii_of_string arg)).
  Qed.
End AbstractComposition.
