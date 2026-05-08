(** [Inline_blocks] — see [.mli]. Pure rendering + simple parsers for
    the four ADR-011 in-file sections. *)

type tier_distribution = {
  tier_a : int;
  tier_b : int;
  tier_c : int;
}

type status = {
  version_n        : int;
  state            : string;
  tier_dist        : tier_distribution;
  pending_user_edits : int;
  last_activity    : string;
  open_tradeoffs   : int;
}

let timestamp_now () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02d-%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

let render_tier_dist td =
  Printf.sprintf "Tier-A=%d, Tier-B=%d, Tier-C=%d"
    td.tier_a td.tier_b td.tier_c

let render_status (s : status) : string =
  let buf = Buffer.create 256 in
  Buffer.add_string buf "## k4k:status\n";
  Buffer.add_string buf
    (Printf.sprintf "- Version: %d\n" s.version_n);
  Buffer.add_string buf
    (Printf.sprintf "- State: %s\n" s.state);
  Buffer.add_string buf
    (Printf.sprintf "- Tiers: %s\n" (render_tier_dist s.tier_dist));
  Buffer.add_string buf
    (Printf.sprintf "- Pending user edits (queued): %d\n"
       s.pending_user_edits);
  Buffer.add_string buf
    (Printf.sprintf "- Open tradeoff proposals: %d\n" s.open_tradeoffs);
  Buffer.add_string buf
    (Printf.sprintf "- Last activity: %s\n\n" s.last_activity);
  Buffer.add_string buf "### User control directives\n";
  Buffer.add_string buf
    "(Write `request: rollback` to abort the in-flight version, \
     or `request: pause` to halt the gap-step loop without reverting.)\n";
  Buffer.contents buf

(* --- directive parsing --- *)

type directive = [ `Rollback | `Pause | `Other of string ]

let lower s = String.lowercase_ascii s

let strip_lead s =
  let n = String.length s in
  let rec go i =
    if i >= n then i
    else match s.[i] with ' ' | '\t' -> go (i + 1) | _ -> i
  in
  let i = go 0 in
  String.sub s i (n - i)

let parse_one_directive line =
  let t = String.trim line in
  let t =
    if String.length t > 0 && t.[0] = '-' then strip_lead (String.sub t 1 (String.length t - 1))
    else t
  in
  let l = lower t in
  let prefix = "request:" in
  let lp = String.length prefix in
  if String.length l >= lp && String.sub l 0 lp = prefix then
    let rest = String.trim
      (String.sub t lp (String.length t - lp)) in
    match lower rest with
    | "rollback" -> Some `Rollback
    | "pause"    -> Some `Pause
    | other      -> Some (`Other other)
  else None

let parse_directives s =
  String.split_on_char '\n' s
  |> List.filter_map parse_one_directive

(* --- version block --- *)

type version_block = {
  number       : int;
  state        : string;
  d_hash       : string;
  tier_dist    : tier_distribution;
  property_count : int;
  completion_state : string;
  audit_path   : string;
}

let render_version (v : version_block) : string =
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf "## k4k:version:%d\n" v.number);
  Buffer.add_string buf
    (Printf.sprintf "- D-hash: %s\n" v.d_hash);
  Buffer.add_string buf
    (Printf.sprintf "- State: %s\n" v.state);
  Buffer.add_string buf
    (Printf.sprintf "- Tiers: %s\n" (render_tier_dist v.tier_dist));
  Buffer.add_string buf
    (Printf.sprintf "- Properties: %d\n" v.property_count);
  Buffer.add_string buf
    (Printf.sprintf "- Completion: %s\n" v.completion_state);
  Buffer.add_string buf
    (Printf.sprintf "- Audit: %s\n" v.audit_path);
  Buffer.contents buf

let render_version_summary_line (v : version_block) =
  Printf.sprintf "- v%d: %s; %s; %d properties; %s\n"
    v.number v.state (render_tier_dist v.tier_dist)
    v.property_count v.completion_state

(* --- tradeoff proposal --- *)

type tradeoff = {
  timestamp        : string;
  property_id      : string;
  why_a_failed     : string;
  proposed_tier    : [ `B | `C ];
  whats_lost       : string;
  whats_gained     : string;
}

let proposed_label = function `B -> "Tier B" | `C -> "Tier C"

let render_tradeoff (t : tradeoff) : string =
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf "## k4k:tradeoff:proposal:%s\n" t.timestamp);
  Buffer.add_string buf
    (Printf.sprintf "- Property: %s\n" t.property_id);
  Buffer.add_string buf
    (Printf.sprintf "- Why Tier A failed: %s\n" t.why_a_failed);
  Buffer.add_string buf
    (Printf.sprintf "- Proposed tier: %s\n" (proposed_label t.proposed_tier));
  Buffer.add_string buf
    (Printf.sprintf "- What is lost: %s\n" t.whats_lost);
  Buffer.add_string buf
    (Printf.sprintf "- What is gained: %s\n\n" t.whats_gained);
  Buffer.add_string buf "Approval: Pending\n";
  Buffer.add_string buf
    "(Reply by editing this block: write `Approved: Tier B` or \
     `Approved: Tier C` to accept, or `Rejected: <guidance>` to \
     reject; then save the file.)\n";
  Buffer.contents buf

let starts_with prefix s =
  let lp = String.length prefix and ls = String.length s in
  ls >= lp && String.sub s 0 lp = prefix

let parse_tradeoff_resolution s =
  let lines = String.split_on_char '\n' s in
  let rec scan = function
    | [] -> `Pending
    | l :: rest ->
        let t = String.trim l in
        if starts_with "Approved:" t then
          let rest_str = String.trim
            (String.sub t 9 (String.length t - 9)) in
          let lr = lower rest_str in
          if lr = "tier b" || lr = "b" then `Approved `B
          else if lr = "tier c" || lr = "c" then `Approved `C
          else `Rejected ("unrecognized tier: " ^ rest_str)
        else if starts_with "Rejected:" t then
          let g = String.trim (String.sub t 9 (String.length t - 9)) in
          `Rejected g
        else scan rest
  in
  scan lines
