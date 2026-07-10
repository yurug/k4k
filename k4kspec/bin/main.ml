open K4kspec

let usage =
  "k4kspec — reference-free spec-validation harness (v1 WIP)\n\n\
   <spec> below is a path to a .k4kspec FILE, or a built-in spec name.\n\n\
   usage:\n\
  \  k4kspec list                        list the built-in specs\n\
  \  k4kspec check <spec>                validate (examples + stability +\n\
  \                                      under-spec report + adversarial sweep)\n\
  \  k4kspec check <spec> --ref '<cmd>'  also run the OPTIONAL clone differential\n\
  \  k4kspec run   <spec> -- <args...>   execute the spec as its own model\n\n\
   built-in specs: " ^ String.concat ", " (List.map fst Specs.by_name) ^ "\n"

let read_file_opt p =
  try let ic = open_in_bin p in let n = in_channel_length ic in
    let s = really_input_string ic n in close_in ic; Some s
  with _ -> None

(* resolve a CLI argument to a spec: an existing file is parsed; otherwise it is a
   built-in spec name. *)
let load (arg : string) : Ast.spec =
  if Sys.file_exists arg then
    (match read_file_opt arg with
     | None -> Printf.eprintf "[k4kspec] cannot read %s\n" arg; exit 2
     | Some src ->
         (try Parse.parse src
          with Parse.Parse_error m -> Printf.eprintf "[k4kspec] parse error in %s: %s\n" arg m; exit 2))
  else
    match List.assoc_opt arg Specs.by_name with
    | Some sp -> sp
    | None ->
        Printf.eprintf "[k4kspec] no such spec or file: %s  (built-ins: %s)\n"
          arg (String.concat ", " (List.map fst Specs.by_name));
        exit 2

let do_check arg rest =
  let sp = load arg in
  let ok = Check.run_report sp in
      (match rest with
       | "--ref" :: cmd :: _ ->
           print_newline ();
           Printf.printf "[clone differential vs %S]  (OPTIONAL — clones only)\n" cmd;
           (match Refdiff.diff sp cmd with
            | Error e -> Printf.printf "  skipped: %s\n" e
            | Ok [] -> Printf.printf "  no divergence on stdout/exit across the sweep\n"
            | Ok ds ->
                List.iter (fun (d : Refdiff.div) ->
                    Printf.printf "  DIVERGE argv=[%s] %s: spec=%s ref=%s\n"
                      (String.concat "; " d.argv) d.field d.want d.got) ds)
       | _ -> ());
      exit (if ok then 0 else 1)

let do_run arg args =
  let sp = load arg in
      let inp = { Eval.argv = args; stdin = ""; read_file = read_file_opt } in
      (match
         (try `Ok (Eval.run_traced sp inp) with
          | Eval.Spec_error m -> `Err m
          | Eval.Undetermined idx -> `Undet idx)
       with
       | `Err m -> Printf.eprintf "[k4kspec] %s: spec error: %s\n" sp.Ast.name m; exit 64
       | `Undet idx ->
           Printf.eprintf
             "[k4kspec] %s: input matches case #%d, whose output is LAW-CONSTRAINED (under-determined) — \
              the spec admits several outputs, so it is not executable as a model on this input. \
              Build the certified implementation instead: `k4kspec certify-agent %s`.\n"
             sp.Ast.name idx sp.Ast.name;
           exit 64
       | `Ok (r, idx) ->
           (* the spec's OWN stdout / (pinned) stderr — the program's real output *)
           print_string r.Eval.rstdout;
           (match r.Eval.rstderr with Eval.SExact s -> output_string stderr s | Eval.SPred _ -> ());
           flush stdout;
           (* operator diagnostics (NOT the spec's stderr): why this happened + the signal *)
           let guard = Check.describe_guard (List.nth sp.Ast.cases idx).Ast.guard in
           let serr = match r.Eval.rstderr with
             | Eval.SExact _ -> "pinned"
             | Eval.SPred p -> Printf.sprintf "free/uncertified (%s)" (Check.pred_name p) in
           Printf.eprintf "[k4kspec] %s: case #%d [%s] -> exit=%d, stdout=%d bytes, stderr=%s\n"
             sp.Ast.name idx guard r.Eval.rexit (String.length r.Eval.rstdout) serr;
           exit r.Eval.rexit)

let () =
  match Array.to_list Sys.argv with
  | _ :: "list" :: _ -> List.iter (fun (n, _) -> print_endline n) Specs.by_name
  | _ :: "emit" :: arg :: _ -> print_string (Rocq_emit.emit (load arg))   (* generated Rocq .v *)
  | _ :: "certify" :: arg :: _ ->
      let r = Certify.certify (load arg) in
      List.iter print_endline r.Certify.log;
      print_endline (if r.Certify.ok then "CERTIFY: OK" else "CERTIFY: FAILED");
      exit (if r.Certify.ok then 0 else 1)
  | _ :: "certify-agent" :: "--compositional" :: arg :: _ ->
      (* COMPOSITIONAL methodology (ADR-021): decompose into certified components -> module-interface
         gate -> certify each -> assemble. *)
      let sp = load arg in
      let backend = match Sys.getenv_opt "K4K_PROOF_CMD" with
        | Some cmd -> Agent_proof.external_backend cmd
        | None -> Agent_proof.stub_backend sp in
      let r = Agent_proof.certify_compositional ~backend sp in
      List.iter print_endline r.Certify.log;
      print_endline (if r.Certify.ok then "CERTIFY-AGENT: OK" else "CERTIFY-AGENT: FAILED");
      exit (if r.Certify.ok then 0 else 1)
  | _ :: "certify-agent" :: "--structured" :: arg :: _ ->
      (* STRUCTURED methodology (ADR-020): implement-naive -> skeleton gate -> fill -> assemble. *)
      let sp = load arg in
      let backend = match Sys.getenv_opt "K4K_PROOF_CMD" with
        | Some cmd -> Agent_proof.external_backend cmd
        | None -> Agent_proof.stub_backend sp in
      let r = Agent_proof.certify_structured ~backend sp in
      List.iter print_endline r.Certify.log;
      print_endline (if r.Certify.ok then "CERTIFY-AGENT: OK" else "CERTIFY-AGENT: FAILED");
      exit (if r.Certify.ok then 0 else 1)
  | _ :: "certify-agent" :: arg :: _ ->
      (* one-shot: agent proposes run + proof; coqc is the gate. Backend from $K4K_PROOF_CMD, else a stub. *)
      let sp = load arg in
      let backend = match Sys.getenv_opt "K4K_PROOF_CMD" with
        | Some cmd -> Agent_proof.external_backend cmd
        | None -> Agent_proof.stub_backend sp in
      let r = Agent_proof.certify ~backend sp in
      List.iter print_endline r.Certify.log;
      print_endline (if r.Certify.ok then "CERTIFY-AGENT: OK" else "CERTIFY-AGENT: FAILED");
      exit (if r.Certify.ok then 0 else 1)
  | _ :: "check" :: name :: rest -> do_check name rest
  | _ :: "run" :: name :: "--" :: args -> do_run name args
  | _ -> print_string usage; exit 2
