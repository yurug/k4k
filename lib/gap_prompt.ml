(** [Gap_prompt] — pure: compose a [prompts/gap-step.md] body for a
    property + characterization. *)

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

let compose (p : Property.t) (d : Characterization.t)
    ~current_summary : string =
  Prompts.render "gap-step.md"
    [ "property_id", p.id;
      "property_statement", p.statement;
      "aspect_path", String.concat "/" p.source.path;
      "current_source_summary", current_summary;
      "acceptance_examples", render_examples (acceptance_lines d);
      "refusing_examples", render_examples (refusing_lines d);
      "test_name_convention",
        "tests must be named P<id>_<slug>; <id> = "
        ^ p.id ^ " (the P + 7-hex-char prefix)" ]
