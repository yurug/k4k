(** [Audit_md] — pure renderer for the per-version
    [audit.md] artefact at [.k4k/version/<n>/audit.md] (ADR-013 §3).

    Produced on version completion or rollback. Contains a one-line
    summary header, the version's manifest pointers, and a Markdown
    table of per-property results. *)

type per_property = {
  id     : string;
  status : string;
  tier   : string;
  commit : string option;
}

type t = {
  version_number : int;
  d_hash         : string;
  baseline_sha   : string;
  branch_name    : string;
  tag_name       : string option;
  properties     : per_property list;
  outcome        : string;
  duration_ms    : int;
}

val render : t -> string
