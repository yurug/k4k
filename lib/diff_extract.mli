(** [Diff_extract] — pure helpers for the [Gap_step] prompt's output
    shape (per [prompts/gap-step.tier-{a,b,c}.md]).

    Two pieces are extracted:
    - the JSON preface listing files touched (sanity check before
      apply);
    - the first unified-diff block. *)

(** [extract_files s] returns [["a.ml"; "b.ml"]] from a JSON preface
    [{"files": [...]}]; returns [[]] when the preface is missing or
    malformed. *)
val extract_files : string -> string list

(** [extract_diff s] returns [Some patch] when a unified-diff block is
    present (fenced ```diff or unfenced lines starting with [--- ]).
    [None] otherwise. *)
val extract_diff : string -> string option
