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
