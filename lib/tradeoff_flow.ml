(** [Tradeoff_flow] — v2 batch 4b: Tier-A→B/C tradeoff proposal +
    sign-off polling (ADR-011 §5).

    When [Gap_step.step] returns [Tradeoff], the [Version_loop] driver
    composes a proposal record, splices it into the interaction file
    via cotype, and pauses until the user writes an [Approved: Tier B]
    or [Rejected: <guidance>] line. The polling loop is bounded by
    [poll_max_iters * poll_interval_s]; once exceeded, the proposal is
    treated as rejected with a synthetic timeout reason.

    Test hook ([K4K_TEST_TRADEOFF_AUTOAPPROVE]): when set, polling is
    short-circuited to the documented value (one of [tier-b],
    [tier-c], [reject:<reason>]). This is the integration-test seam
    that lets [S3_tradeoff_proposal_signed_off] exercise the full
    flow without a second cotype client. *)

type proposal = {
  property_id    : string;
  why_a_failed   : string;
  proposed_tier  : [ `B | `C ];
  whats_lost     : string;
  whats_gained   : string;
}

type resolution =
  | Approved of [ `B | `C ]
  | Rejected of string
  | Timed_out

let render_block ~ts (p : proposal) =
  let to_t : Inline_blocks.tradeoff = {
    timestamp = ts;
    property_id = p.property_id;
    why_a_failed = p.why_a_failed;
    proposed_tier = p.proposed_tier;
    whats_lost = p.whats_lost;
    whats_gained = p.whats_gained;
  } in
  Inline_blocks.render_tradeoff to_t

let splice_proposal ~cotype ~file_path ~bytes_to_append =
  try
    let opened = Cotype.open_ cotype ~file:file_path in
    match opened with
    | Error _ -> false
    | Ok r ->
        let base = Persist.read_file r.base_path in
        let needs_nl =
          let n = String.length base in
          n > 0 && base.[n - 1] <> '\n' in
        let merged =
          if needs_nl then base ^ "\n" ^ bytes_to_append
          else base ^ bytes_to_append in
        (match Cotype.save cotype ~file:file_path
                 ~base_sha:r.base_sha ~actor:"agent:k4k"
                 ~bytes:merged with
         | Ok _ -> true | Error _ -> false)
  with _ -> false

let parse_test_hook () : resolution option =
  match Sys.getenv_opt "K4K_TEST_TRADEOFF_AUTOAPPROVE" with
  | None | Some "" -> None
  | Some s ->
      let lc = String.lowercase_ascii (String.trim s) in
      if lc = "tier-b" || lc = "b" then Some (Approved `B)
      else if lc = "tier-c" || lc = "c" then Some (Approved `C)
      else if String.length lc > 7 && String.sub lc 0 7 = "reject:"
      then Some (Rejected (String.sub s 7 (String.length s - 7)))
      else if lc = "timeout" then Some Timed_out
      else None

let read_current ~cotype ~file_path =
  try Some (Cotype.read_base cotype ~file:file_path)
  with _ -> None

let poll_once ~cotype ~file_path : resolution option =
  match read_current ~cotype ~file_path with
  | None -> None
  | Some content ->
      (match Inline_blocks_sections.find_tradeoff_block content with
       | None -> None
       | Some (_ts, body, _start, _stop) ->
           (match Inline_blocks.parse_tradeoff_resolution body with
            | `Approved t -> Some (Approved t)
            | `Rejected g -> Some (Rejected g)
            | `Pending -> None))

let sleep_s s =
  ignore (Unix.select [] [] [] s)

let rec wait_loop ~cotype ~file_path ~poll_interval_s ~max_iters n =
  if n >= max_iters then Timed_out
  else
    match poll_once ~cotype ~file_path with
    | Some r -> r
    | None ->
        sleep_s poll_interval_s;
        wait_loop ~cotype ~file_path ~poll_interval_s ~max_iters (n + 1)

let archive_proposal ~k4k_dir ~version_n ~ts ~block_text =
  let dir = Version_persist.tradeoffs_dir ~k4k_dir ~number:version_n in
  Persist.ensure_dir dir;
  let p = Filename.concat dir (ts ^ ".md") in
  Persist.atomic_write ~path:p block_text

let archive_and_breadcrumb ~cotype ~file_path ~k4k_dir ~version_n ~ts =
  match read_current ~cotype ~file_path with
  | None -> ()
  | Some content ->
      (match Inline_blocks_sections.find_tradeoff_block content with
       | None -> ()
       | Some (_ts2, body, start, stop) ->
           let block_text = String.sub content start (stop - start) in
           archive_proposal ~k4k_dir ~version_n ~ts ~block_text;
           let _ = body in
           let bc = Inline_blocks_sections.breadcrumb_for "tradeoff" ts in
           let new_content =
             String.sub content 0 start ^ bc ^ "\n"
             ^ String.sub content stop (String.length content - stop)
           in
           (try
              let opened = Cotype.open_ cotype ~file:file_path in
              match opened with
              | Error _ -> ()
              | Ok r ->
                  let _ = Cotype.save cotype ~file:file_path
                            ~base_sha:r.base_sha ~actor:"agent:k4k"
                            ~bytes:new_content in ()
            with _ -> ()))

(** [propose_and_wait ~cotype ~file_path ~k4k_dir ~version_n ~emit
    ~proposal] — splice the proposal block into the file, wait for the
    user's reply (or test-hook short-circuit), archive on resolution,
    and return the resolution. *)
let propose_and_wait ~cotype ~file_path ~k4k_dir ~version_n ~emit
    ~proposal : resolution =
  let ts = Inline_blocks.timestamp_now () in
  let block = render_block ~ts proposal in
  emit "tradeoff.proposed"
    (`Assoc [ "property_id", `String proposal.property_id;
              "ts", `String ts ]);
  let _ = splice_proposal ~cotype ~file_path
            ~bytes_to_append:block in
  let r = match parse_test_hook () with
    | Some r -> r
    | None ->
        wait_loop ~cotype ~file_path
          ~poll_interval_s:0.25 ~max_iters:240 0
  in
  archive_and_breadcrumb ~cotype ~file_path ~k4k_dir ~version_n ~ts;
  emit "tradeoff.resolved"
    (`Assoc [ "property_id", `String proposal.property_id;
              "ts", `String ts;
              "outcome",
              `String (match r with
                | Approved `B -> "approved-tier-b"
                | Approved `C -> "approved-tier-c"
                | Rejected _ -> "rejected"
                | Timed_out -> "timed-out") ]);
  r
