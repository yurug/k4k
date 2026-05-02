(** [Divergence] — diff and serialize two formalization-run results
    per [kb/properties/edge-cases.md#T10] and ADR-005.

    Pure; no I/O. Persistence belongs to [Persist.write_divergence_report]. *)

type t = {
  run_a_id   : string;
  run_b_id   : string;
  hash_a     : string;
  hash_b     : string;
  diff_paths : string list;     (** JSON-pointer-ish paths to differing nodes *)
}

(** [diff a b] — slash-delimited paths into the JSON trees where they
    differ. Deterministic walk order (objects: keys lex-sorted; arrays:
    index order). Returns at least one path when the trees are not equal.

    @invariant P18 — the comparison is deterministic and total. *)
val diff : Yojson.Safe.t -> Yojson.Safe.t -> string list

(** [to_yojson d] — serialize a divergence report. *)
val to_yojson : t -> Yojson.Safe.t
