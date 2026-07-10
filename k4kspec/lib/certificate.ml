(* Certificate — the deliverable document for a SIGNED, certified spec version
   (certificates/v<N>/certificate.md). Extends the TCB manifest with what ADR-016 §13 calls
   certificate-scope disclosure: channel by channel, what "certified" covers — computed from
   the spec, never prose. The one unforgivable bug would be a waived law weakening spec_rel
   without disclosure: the Waivers section below is derived from the SAME signature record
   whose waivers drove `Sign.apply_waivers`, so they cannot diverge. *)

open Ast

(* classification of one channel of one case, against the ORIGINAL (unwaived) spec *)
let classify (c : case) (case_i : int) (ch : chan) (waived : (int * int) list) : string =
  let laws_on_ch =
    List.filter (fun (_, l) -> Check.law_mentions ch l) (List.mapi (fun j l -> (j, l)) c.laws)
  in
  let active, waived_here =
    List.partition (fun (j, _) -> not (List.mem (case_i, j) waived)) laws_on_ch
  in
  match List.assoc_opt ch c.outs with
  | Some (Eq _) -> "CERTIFIED (pinned)"
  | Some (P p) -> (
      match active, waived_here with
      | [], [] ->
          (match p with
           | Any -> "FREE — uncertified"
           | _ -> Printf.sprintf "FREE — uncertified (%s)" (Check.pred_name p))
      | active, [] ->
          Printf.sprintf "CERTIFIED-BY-LAW (%d law(s), proof-discharged)" (List.length active)
      | active, w ->
          Printf.sprintf "%s; %d law(s) WAIVED — see Waivers"
            (if active = [] then "NOT VERIFIED" else Printf.sprintf "CERTIFIED-BY-LAW (%d law(s))" (List.length active))
            (List.length w))
  | None -> "?"

let render ~(sp : spec) ~(signature : Sign.signature) ~(sig_path : string)
    ~(hints_present : bool) ~(tcb : string) ~(log : string list) : string =
  let b = Buffer.create 2048 in
  let p fmt = Printf.ksprintf (fun s -> Buffer.add_string b s; Buffer.add_char b '\n') fmt in
  let waived = List.map (fun w -> (w.Sign.case_i, w.Sign.law_j)) signature.Sign.waivers in
  let log_line pfx = List.find_opt (fun l -> String.length l >= String.length pfx && String.sub l 0 (String.length pfx) = pfx) log in
  p "# k4k certificate — %s, spec version v%d" sp.name signature.Sign.version;
  p "";
  p "Signed spec : %s   sha256 %s" signature.Sign.spec_file signature.Sign.spec_hash;
  p "Signature   : %s   signer %s   %s" sig_path signature.Sign.signer signature.Sign.date;
  p "Statement   : correct : forall i, spec_rel i (run i)";
  (match log_line "certificate gate:" with
   | Some l -> p "              (%s)" l
   | None -> ());
  (match log_line "binary MATCHES" with
   | Some l -> p "Cross-check : %s" l
   | None -> ());
  p "";
  p "## Scope — what \"certified\" covers, channel by channel";
  p "";
  p "| case | guard | stdout | stderr | exit |";
  p "|------|-------|--------|--------|------|";
  List.iteri
    (fun i (c : case) ->
      p "| #%d | %s | %s | %s | %s |" i
        (Check.describe_guard c.guard)
        (classify c i Stdout waived) (classify c i Stderr waived) (classify c i Exit waived))
    sp.cases;
  let free = Check.free_dims sp in
  if free <> [] then begin
    p "";
    p "FREE channels were acknowledged at sign-off (%s):" (Filename.basename sig_path);
    List.iter
      (fun (i, ch, pr) ->
        p "  case#%d %s (%s) — content is agent-authored, NOT part of the certified contract,"
          i (Check.chan_name ch) (Check.pred_name pr);
        p "  and may change between versions.")
      (List.filter
         (fun (i, ch, _) -> not (List.exists (Check.law_mentions ch) (List.nth sp.cases i).laws))
         free)
  end;
  p "";
  p "## Waivers";
  if signature.Sign.waivers = [] then p "(none)"
  else
    List.iter
      (fun w ->
        let law_txt =
          match List.nth_opt sp.cases w.Sign.case_i with
          | Some c -> (match List.nth_opt c.laws w.Sign.law_j with
                       | Some l -> Check.describe_expr l
                       | None -> "?")
          | None -> "?"
        in
        p "case#%d.law#%d — tier %s — **NOT formally verified.**" w.Sign.case_i w.Sign.law_j w.Sign.tier;
        p "  law: %s" law_txt;
        p "  This law was REMOVED from the certified statement spec_rel. k4k v1 has no";
        p "  tier-B/C execution harness: NO property testing was run for this law; it rests";
        p "  solely on the signer's rationale:";
        p "  %S" w.Sign.rationale)
      signature.Sign.waivers;
  p "";
  p "## Trusted base (TCB)";
  p "";
  Buffer.add_string b tcb;
  p "";
  p "## Not covered by this certificate";
  (if hints_present then (
     match signature.Sign.hints_file, signature.Sign.hints_hash with
     | Some f, Some h ->
         p "- guidance (%s, sha256 %s): uncertified, best-effort, may change between" f (String.sub h 0 12);
         p "  versions; do not depend on guidance-governed output."
     | _ ->
         p "- guidance file present but NOT covered by the signature: uncertified, best-effort.")
   else p "- no guidance file. FREE channels above carry agent-authored, uncertified content.");
  p "- non-observable obligations (secret erasure, constant time, resource bounds): not";
  p "  statable in an observational spec; neither checked nor waived here.";
  Buffer.contents b
