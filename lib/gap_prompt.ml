(** [Gap_prompt] — pure: compose the tier-aware gap-step prompt body
    for a property + characterization (ADR-012). The default tier is
    A; B and C are entered only after a user-signed tradeoff proposal
    (ADR-011 §5). *)

let template_for = function
  | `A -> "gap-step.tier-a.md"
  | `B -> "gap-step.tier-b.md"
  | `C -> "gap-step.tier-c.md"

let render_examples xs =
  match xs with
  | [] -> "(none)"
  | _ ->
      String.concat "\n"
        (List.mapi (fun i s -> Printf.sprintf "%d. %s" (i + 1) s) xs)

let acceptance_lines (d : Characterization.t) =
  List.map (fun (a : Characterization.acceptance_example) ->
    Printf.sprintf "argv=%s -> stdout=%S exit=%d"
      (String.concat "," a.argv)
      a.expect.stdout a.expect.exit_code)
    d.examples_accept

let refusing_lines (d : Characterization.t) =
  List.map (fun (r : Characterization.refusing_example) ->
    Printf.sprintf "argv=%s -> error=%s"
      (String.concat "," r.argv) r.expect_error)
    d.examples_refuse

(* Ralph-loop feedback (v2 batch 26): on a retry, the agent gets a
   summary of the prior attempt's failure and the current strike
   count. On the first attempt these collapse to "(none)" so the
   prompt shape stays uniform. *)
let prior_failure_block (p : Property.t) =
  match p.last_failure_reason with
  | None -> "(none — this is the first attempt)"
  | Some reason ->
      Printf.sprintf
        "Strike %d/3. The previous attempt was rejected because:\n  \
         %s\n\
         Diagnose the cause and produce a different patch — do NOT \
         resubmit the same shape. Common causes: the diff did not \
         apply (path or context wrong), the verifier did not return \
         status \"established\" for property %s, the patch \
         regressed an already-established property, or your response \
         contained no valid unified-diff block."
        p.failure_count reason p.id

let compose ?(tier = `A) (p : Property.t) (d : Characterization.t)
    ~current_summary : string =
  let language = if d.language = "" then "(unspecified)" else d.language in
  let verifier_command =
    if d.verifier_command = [] then "(unspecified)"
    else String.concat " " d.verifier_command
  in
  let _ = render_examples (acceptance_lines d) in
  let _ = render_examples (refusing_lines d) in
  Prompts.render (template_for tier)
    [ "property_id", p.id;
      "property_statement", p.statement;
      "aspect_path", String.concat "/" p.source.path;
      "language", language;
      "verifier_command", verifier_command;
      "prior_failure", prior_failure_block p;
      "current_source_summary", current_summary; ]
