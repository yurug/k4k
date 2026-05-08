(** [Audit_md] — pure renderer for [.k4k/version/<n>/audit.md]
    (ADR-013 §3). Human-readable per-property summary. *)

type per_property = {
  id     : string;
  status : string;     (** "established" | "blocked" | "unknown" *)
  tier   : string;     (** "A" | "B" | "C" *)
  commit : string option;
}

type t = {
  version_number : int;
  d_hash         : string;
  baseline_sha   : string;
  branch_name    : string;
  tag_name       : string option;
  properties     : per_property list;
  outcome        : string;     (** "done" | "rolled-back" | "in-flight" *)
  duration_ms    : int;
}

let opt_string = function None -> "—" | Some s -> s

let render (t : t) : string =
  let buf = Buffer.create 1024 in
  Buffer.add_string buf
    (Printf.sprintf "# k4k version %d audit\n\n" t.version_number);
  Buffer.add_string buf
    (Printf.sprintf "- D-hash: `%s`\n" t.d_hash);
  Buffer.add_string buf
    (Printf.sprintf "- Baseline commit: `%s`\n" t.baseline_sha);
  Buffer.add_string buf
    (Printf.sprintf "- Branch: `%s`\n" t.branch_name);
  Buffer.add_string buf
    (Printf.sprintf "- Tag: %s\n" (opt_string t.tag_name));
  Buffer.add_string buf
    (Printf.sprintf "- Outcome: %s\n" t.outcome);
  Buffer.add_string buf
    (Printf.sprintf "- Duration: %d ms\n\n" t.duration_ms);
  Buffer.add_string buf "## Per-property results\n\n";
  Buffer.add_string buf "| Property | Tier | Status | Commit |\n";
  Buffer.add_string buf "|----------|------|--------|--------|\n";
  List.iter (fun p ->
    Buffer.add_string buf
      (Printf.sprintf "| %s | %s | %s | %s |\n"
         p.id p.tier p.status (opt_string p.commit))
  ) t.properties;
  Buffer.contents buf
