(** [Inline_blocks] — pure renderers + parsers for the four k4k-managed
    in-file section patterns introduced by ADR-011 §5:

    - [## k4k:status]                   live status (replaced each tick)
    - [## k4k:version:<n>]              version snapshots (accumulating)
    - [## k4k:clarification:<ts>]       (rendered by [Clarification])
    - [## k4k:tradeoff:proposal:<ts>]   tier-A→B/C proposals

    All rendering is pure-string; concurrent file mutation flows through
    [Cotype.save] (P1, P12). The user reads these blocks and writes
    documented control directives inside [## k4k:status] or replies
    inline inside a tradeoff block.

    @invariant P1 — only k4k-managed sections are produced/parsed here. *)

(** {1 Status block} *)

type tier_distribution = {
  tier_a : int;
  tier_b : int;
  tier_c : int;
}

type status = {
  version_n        : int;
  state            : string;       (** state name: "developing" etc. *)
  tier_dist        : tier_distribution;
  pending_user_edits : int;
  last_activity    : string;       (** ISO-8601 *)
  open_tradeoffs   : int;
}

val render_status : status -> string

(** {2 Reading user control directives}

    The status block contains a "User control directives" subsection
    where the user writes free-form lines like [request: rollback] or
    [request: pause]. The parser is line-based: any line matching
    [request: <verb>] (case-insensitive) yields one entry. *)

type directive = [ `Rollback | `Pause | `Other of string ]

val parse_directives : string -> directive list

(** {1 Version block} *)

type version_block = {
  number       : int;
  state        : string;
  d_hash       : string;
  tier_dist    : tier_distribution;
  property_count : int;
  completion_state : string;
  audit_path   : string;
}

val render_version : version_block -> string

(** {1 Tradeoff-proposal block} *)

type tradeoff = {
  timestamp        : string;
  property_id      : string;
  why_a_failed     : string;
  proposed_tier    : [ `B | `C ];
  whats_lost       : string;
  whats_gained     : string;
}

val render_tradeoff : tradeoff -> string

(** [parse_tradeoff_resolution s] reads an [Approval:] / [Approved:] /
    [Rejected:] line in the body of a tradeoff block. Returns:
    - [`Approved tier] on [Approved: Tier B] / [Approved: Tier C]
    - [`Rejected guidance] on [Rejected: <free-form>]
    - [`Pending] when none of the resolution lines are present *)

val parse_tradeoff_resolution :
  string -> [ `Approved of [ `B | `C ] | `Rejected of string | `Pending ]

(** {1 Past-versions summary line (after 3+ versions)} *)

val render_version_summary_line : version_block -> string

(** {1 Common ts helper} *)

val timestamp_now : unit -> string
