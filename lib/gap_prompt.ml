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
      "current_source_summary", current_summary; ]
