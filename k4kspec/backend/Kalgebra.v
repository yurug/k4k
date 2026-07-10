(* Kalgebra — the blessed value algebra, in Rocq, AUDITED ONCE.
   This is the certified vocabulary every generated spec is stated in terms of: a k4kspec
   spec MEANS whatever these definitions say. It is part of the TCB and must match the
   reference semantics in k4kspec/lib/algebra.ml. Generated specs `Require Import Kalgebra`
   rather than re-emitting these defs, so the per-spec .v carries only Input/spec_rel/run/proof. *)

Require Import Coq.Strings.String Coq.Strings.Ascii Coq.Lists.List Coq.Arith.PeanoNat Coq.Bool.Bool.
Require Export Coq.Sorting.Permutation Coq.Sorting.Sorted.
Import ListNotations.

Definition bytes := string.

(* byte order, for relational laws (e.g. sorting) *)
Definition ascii_le (a b : ascii) : Prop := nat_of_ascii a <= nat_of_ascii b.
(* STRICT byte order: `Sorted ascii_lt l` forces strictly increasing -> no duplicates *)
Definition ascii_lt (a b : ascii) : Prop := nat_of_ascii a < nat_of_ascii b.

(* partition preorder around the threshold 109 ('m'): "if b is in the small group, so is a".
   Sorted part_le l  <->  l is partitioned (all bytes < 'm' precede all bytes >= 'm'). It is a
   transitive total preorder — the agent must discover and prove that to use it. *)
Definition part_le (a b : ascii) : Prop := nat_of_ascii b < 109 -> nat_of_ascii a < 109.

(* lexicographic byte order on strings, for LINE-sorting laws (`Sorted bytes_le (lines s)`):
   a total preorder (a total order, since nat_of_ascii is injective); duplicates allowed. *)
Fixpoint bytes_le (a b : bytes) : Prop :=
  match a, b with
  | EmptyString, _ => True
  | String _ _, EmptyString => False
  | String x a', String y b' =>
      nat_of_ascii x < nat_of_ascii y \/ (nat_of_ascii x = nat_of_ascii y /\ bytes_le a' b')
  end.
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
Fixpoint unlines (l : list string) : string :=
  match l with nil => EmptyString | x :: r => append x (String nlc (unlines r)) end.
Definition lfirst (p : string -> bool) (l : list string) (d : string) : string :=
  match find p l with Some v => v | None => d end.

(* ============== PROVED LAWS of the algebra (the blessed-laws library, ADR-021) ==============
   Everything in this section is a THEOREM about the definitions above, kernel-checked when this
   file compiles — it adds NOTHING to the TCB (only Definitions are trusted). First harvest
   (2026-07-10): the lines/unlines interaction laws from the grepsort certificate — the roundtrip
   and its side condition, which every line-oriented proof needs. `no_newline` is lemma
   vocabulary (appears only in law statements), not spec vocabulary. *)

Definition no_newline (s : bytes) : Prop := ~ List.In nlc (list_ascii_of_string s).

Lemma splitc_no_delim :
  forall (d : ascii) (s : string),
    Forall (fun p => ~ List.In d (list_ascii_of_string p)) (splitc d s).
Proof.
  intros d s. induction s as [| c r IH]; simpl.
  - constructor.
    + intro H; simpl in H; destruct H.
    + constructor.
  - destruct (Ascii.eqb c d) eqn:Heq.
    + constructor.
      * intro H; simpl in H; destruct H.
      * exact IH.
    + apply Ascii.eqb_neq in Heq.
      revert IH.
      destruct (splitc d r) as [| h t]; simpl; intro IH.
      * constructor.
        { intro H; simpl in H.
          destruct H as [H | H]; [exact (Heq H) | destruct H]. }
        { constructor. }
      * inversion IH as [| ? ? Hh Ht]; subst.
        constructor.
        { intro H; simpl in H.
          destruct H as [H | H]; [exact (Heq H) | exact (Hh H)]. }
        { exact Ht. }
Qed.

Lemma splitc_nlc_no_newline :
  forall s : string, Forall no_newline (splitc nlc s).
Proof.
  intro s. exact (splitc_no_delim nlc s).
Qed.

(* generic Forall conveniences (named *_helper to avoid stdlib clashes) *)
Lemma Forall_app_helper :
  forall (A : Type) (P : A -> Prop) (l1 l2 : list A),
    Forall P l1 -> Forall P l2 -> Forall P (l1 ++ l2).
Proof.
  intros A P l1 l2 H1 H2.
  induction H1 as [| x l1' HPx HF IH]; simpl.
  - exact H2.
  - constructor; [exact HPx | exact IH].
Qed.

Lemma Forall_rev_helper :
  forall (A : Type) (P : A -> Prop) (l : list A),
    Forall P l -> Forall P (rev l).
Proof.
  intros A P l H.
  induction H as [| x l' HPx HF IH]; simpl.
  - constructor.
  - apply Forall_app_helper.
    + exact IH.
    + constructor; [exact HPx | constructor].
Qed.

Lemma Forall_tail_helper :
  forall (A : Type) (P : A -> Prop) (x : A) (l : list A),
    Forall P (x :: l) -> Forall P l.
Proof.
  intros A P x l H.
  inversion H; subst; assumption.
Qed.

Lemma Forall_drop_last_empty :
  forall (P : string -> Prop) (l : list string),
    Forall P l -> Forall P (drop_last_empty l).
Proof.
  intros P l H.
  unfold drop_last_empty.
  destruct (rev l) as [| h t] eqn:Hrev.
  - exact H.
  - destruct h as [| c r].
    + assert (Ht : Forall P (EmptyString :: t)).
      { rewrite <- Hrev. apply Forall_rev_helper. exact H. }
      exact (Forall_rev_helper _ P t
               (Forall_tail_helper _ P EmptyString t Ht)).
    + exact H.
Qed.

(* every element of a `lines` result is newline-free — supplies the roundtrip side condition *)
Lemma lines_no_newline : forall s, Forall no_newline (lines s).
Proof.
  intro s. unfold lines. destruct s as [| c r].
  - constructor.
  - apply Forall_drop_last_empty. apply splitc_nlc_no_newline.
Qed.

Lemma splitc_app_nl :
  forall s t, no_newline s ->
    splitc nlc (append s (String nlc t)) = s :: splitc nlc t.
Proof.
  intro s. induction s as [| c s' IH]; intros t H.
  - simpl.
    destruct (Ascii.eqb nlc nlc) eqn:Eq.
    + reflexivity.
    + rewrite Ascii.eqb_refl in Eq. discriminate Eq.
  - unfold no_newline in H. simpl in H.
    assert (Hc : Ascii.eqb c nlc = false).
    { apply (proj2 (Ascii.eqb_neq c nlc)). intro E. apply H. left.
      rewrite E. reflexivity. }
    assert (Hs' : no_newline s').
    { intro Hin. apply H. right. exact Hin. }
    simpl. rewrite Hc.
    rewrite (IH t Hs').
    reflexivity.
Qed.

Lemma splitc_unlines :
  forall l, Forall no_newline l ->
    splitc nlc (unlines l) = (l ++ [EmptyString])%list.
Proof.
  intro l. induction l as [| x r IH]; intro H.
  - reflexivity.
  - inversion H as [| ? ? Hx Hr]; subst.
    simpl.
    rewrite (splitc_app_nl x (unlines r) Hx).
    rewrite (IH Hr).
    reflexivity.
Qed.

Lemma drop_last_empty_app :
  forall l : list string, drop_last_empty (l ++ [EmptyString])%list = l.
Proof.
  intro l. unfold drop_last_empty.
  rewrite rev_app_distr. simpl.
  apply rev_involutive.
Qed.

Lemma unlines_cons_not_empty :
  forall x r, unlines (x :: r) <> EmptyString.
Proof.
  intros x r. destruct x; simpl; discriminate.
Qed.

(* THE roundtrip: lines is a left inverse of unlines on newline-free lines *)
Lemma lines_unlines : forall l, Forall no_newline l -> lines (unlines l) = l.
Proof.
  intros l H. destruct l as [| h t].
  - reflexivity.
  - unfold lines.
    destruct (unlines (h :: t)) as [| c r] eqn:E.
    + exfalso. exact (unlines_cons_not_empty h t E).
    + rewrite <- E.
      rewrite (splitc_unlines (h :: t) H).
      apply drop_last_empty_app.
Qed.
(* ============================== end of the blessed-laws library ============================== *)

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
