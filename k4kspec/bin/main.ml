open K4kspec

let usage =
  "k4kspec — spec-validation + certification harness (v3 product surface)\n\n\
   <spec> below is a path to a .k4kspec FILE, or a built-in spec name.\n\n\
   validate / explore:\n\
  \  k4kspec list                        list the built-in specs\n\
  \  k4kspec check <spec>                validate (examples + stability +\n\
  \                                      under-spec report + adversarial sweep)\n\
  \  k4kspec check <spec> --ref '<cmd>'  also run the OPTIONAL clone differential\n\
  \  k4kspec run   <spec> -- <args...>   execute the spec as its own model\n\
  \  k4kspec emit  <spec>                print the elaborated Rocq statement + run\n\n\
   sign / certify (files only; the human is the sole writer of the spec):\n\
  \  k4kspec sign  <file> [--ack-underspec]\n\
  \                [--waive case#<i>.law#<j>:<B|C> --rationale \"...\"]...\n\
  \                freeze the exact spec bytes as version v<N> (the sign-off act)\n\
  \  k4kspec status <file>               version, signature validity, waivers, certificate\n\
  \  k4kspec certify        [--unsigned] <spec>\n\
  \  k4kspec certify-agent  [--structured|--compositional] [--unsigned] <spec>\n\
  \                certify a SIGNED spec ($K4K_PROOF_CMD drives the prover agent);\n\
  \                --unsigned / built-ins = development run, NOT a certified deliverable\n\n\
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

(* ---- the signature gate for certify paths -------------------------------------
   Built-ins and --unsigned runs are DEVELOPMENT runs (loud manifest stamp, no promotion);
   spec FILES must carry a valid signature over their exact bytes. *)
let gate arg ~unsigned : Sign.signature option =
  if not (Sys.file_exists arg) then None                       (* built-in: development run *)
  else if unsigned then None
  else
    match Sign.verify arg with
    | Sign.Valid (s, _) -> Some s
    | Sign.Unsigned ->
        Printf.eprintf
          "[k4kspec] REFUSE: %s is not signed.\n\
           Review it (k4kspec check %s), then sign it (k4kspec sign %s).\n\
           Nothing was certified. (--unsigned runs it as a development run.)\n"
          arg arg arg;
        exit 3
    | Sign.Mismatch m ->
        Printf.eprintf "[k4kspec] REFUSE: %s\nNothing was certified.\n" m;
        exit 3

let signature_line = function
  | None -> "none — development run, NOT a certified deliverable"
  | Some (s : Sign.signature) ->
      Printf.sprintf "%s v%d sha256 %s (signer %s)%s" s.Sign.spec_file s.Sign.version s.Sign.spec_hash
        s.Sign.signer
        (match s.Sign.waivers with
         | [] -> ""
         | ws -> Printf.sprintf "; %d law(s) WAIVED (tier B/C): removed from the certified statement" (List.length ws))

let do_certify arg ~unsigned ~mode =
  let sg = gate arg ~unsigned in
  let sp0 = load arg in
  (* waivers recorded at sign time weaken WHAT IS PROVEN (single choke point), never what check sees *)
  let waived = match sg with None -> [] | Some s -> List.map (fun w -> (w.Sign.case_i, w.Sign.law_j)) s.Sign.waivers in
  let sp = Sign.apply_waivers sp0 waived in
  let signature = signature_line sg in
  let r =
    match mode with
    | `Det -> Certify.certify ~signature sp
    | `Agent m ->
        let backend =
          match Sys.getenv_opt "K4K_PROOF_CMD" with
          | Some cmd -> Agent_proof.external_backend cmd
          | None -> Agent_proof.stub_backend sp
        in
        (match m with
         | `OneShot -> Agent_proof.certify ~signature ~backend sp
         | `Structured -> Agent_proof.certify_structured ~signature ~backend sp
         | `Compositional -> Agent_proof.certify_compositional ~signature ~backend sp)
  in
  List.iter print_endline r.Certify.log;
  (* a FAILED run on a file persists its honest report — the input to propose-fix *)
  (if (not r.Certify.ok) && Sys.file_exists arg then begin
     Store.write_file (Store.last_failure_path arg)
       (Printf.sprintf "# certify failure — %s\nspec-sha256: %s\ndate: %s\n\n%s\n"
          (Filename.basename arg)
          (Sign.hash_bytes (Store.read_file arg))
          (Store.timestamp ())
          (String.concat "\n" r.Certify.log));
     Printf.eprintf "hint: k4kspec propose-fix %s  (agent drafts a spec-change proposal from this failure)\n" arg
   end);
  (* SIGNED successful runs are PROMOTED into the ledger: certificate.md + the named artifacts
     move from the /tmp workdir to <name>.k4k/certificates/v<N>/. Dev runs stay in /tmp. *)
  (match sg, r.Certify.ok with
   | Some s, true ->
       let workdir = match mode with `Det -> "/tmp/k4k_certify" | `Agent _ -> "/tmp/k4k_certify_agent" in
       let n = sp0.Ast.name in
       let sig_path =
         match Store.latest_signature arg with Some (_, p) -> p | None -> "?" in
       let cert =
         Certificate.render ~sp:sp0 ~signature:s ~sig_path
           ~hints_present:(Sys.file_exists (Store.hints_path arg))
           ~tcb:(try Store.read_file (Filename.concat workdir (n ^ ".tcb.md")) with _ -> "(tcb manifest missing)")
           ~log:r.Certify.log
       in
       let dst =
         Store.promote arg s.Sign.version
           (List.map (fun f -> (Filename.concat workdir f, f))
              [ n ^ ".v"; n ^ "_ext.ml"; n ^ "_main.ml"; n; n ^ ".tcb.md" ])
       in
       Store.write_file (Filename.concat dst "certificate.md") cert;
       Printf.printf "certificate: %s\n" (Filename.concat dst "certificate.md")
   | _ -> ());
  let label = match mode with `Det -> "CERTIFY" | `Agent _ -> "CERTIFY-AGENT" in
  print_endline (label ^ ": " ^ (if r.Certify.ok then "OK" else "FAILED"));
  exit (if r.Certify.ok then 0 else 1)

let () =
  match Array.to_list Sys.argv with
  | _ :: "list" :: _ -> List.iter (fun (n, _) -> print_endline n) Specs.by_name
  | _ :: "emit" :: arg :: _ -> print_string (Rocq_emit.emit (load arg))   (* generated Rocq .v *)
  | _ :: "certify" :: rest ->
      let unsigned = List.mem "--unsigned" rest in
      (match List.filter (fun a -> a <> "--unsigned") rest with
       | [ arg ] -> do_certify arg ~unsigned ~mode:`Det
       | _ -> print_string usage; exit 2)
  | _ :: "certify-agent" :: rest ->
      let unsigned = List.mem "--unsigned" rest in
      (match List.filter (fun a -> a <> "--unsigned") rest with
       | [ "--compositional"; arg ] -> do_certify arg ~unsigned ~mode:(`Agent `Compositional)
       | [ "--structured"; arg ] -> do_certify arg ~unsigned ~mode:(`Agent `Structured)
       | [ arg ] -> do_certify arg ~unsigned ~mode:(`Agent `OneShot)
       | _ -> print_string usage; exit 2)
  | _ :: "propose" :: name :: intent :: _ ->
      let spec_path = name ^ ".k4kspec" in
      if Sys.file_exists spec_path then
        (Printf.eprintf "[k4kspec] REFUSE: %s exists — propose only CREATES; use `k4kspec revise %s \"...\"`\n" spec_path spec_path;
         exit 2);
      let backend = Propose.authoring_backend ~stub:(Propose.stub_propose_backend ~name) in
      (match Propose.propose ~backend ~name ~intent with
       | Error m -> Printf.eprintf "[k4kspec] agent backend unusable after retries:\n%s\n" m; exit 5
       | Ok d ->
           let hints_path = Store.hints_path spec_path in
           Store.write_file spec_path d.Propose.spec_text;
           Store.write_file hints_path d.Propose.hints_text;
           Store.write_file (Store.decisions_path spec_path) d.Propose.decisions_text;
           let record : Record.t =
             { Record.fields =
                 [ ("k4k-proposal", "1"); ("kind", "new"); ("spec", Filename.basename spec_path);
                   ("against-version", "unsigned"); ("date", Store.timestamp ());
                   ("backend", d.Propose.backend_name);
                   ("proposal-check", "parses, check=pass") ];
               sections =
                 [ ("decisions", d.Propose.decisions_text); ("proposed spec", d.Propose.spec_text);
                   ("proposed hints", d.Propose.hints_text) ] }
           in
           Store.write_new (Store.proposal_path spec_path "new") (Record.to_string record);
           Printf.printf "wrote %s        (DRAFT — you are the sole writer; edit it)\n" spec_path;
           Printf.printf "wrote %s           (guidance draft — cosmetic only, uncertified)\n" hints_path;
           Printf.printf "wrote %s   (the agent's decisions — review THESE)\n" (Store.decisions_path spec_path);
           print_newline ();
           print_string d.Propose.decisions_text;
           print_newline ();
           Printf.printf "next: review + edit, then  k4kspec check %s  and  k4kspec sign %s\n" spec_path spec_path;
           exit 0)
  | _ :: "revise" :: file :: request :: _ ->
      if not (Sys.file_exists file) then (Printf.eprintf "[k4kspec] no such file: %s\n" file; exit 2);
      let spec = Store.read_file file in
      let hints_path = Store.hints_path file in
      let hints = if Sys.file_exists hints_path then Store.read_file hints_path else "" in
      let dpath = Store.decisions_path file in
      let decisions = if Sys.file_exists dpath then Store.read_file dpath else "" in
      let backend = Propose.authoring_backend ~stub:Propose.stub_revise_backend in
      (match Propose.revise ~backend ~spec ~hints ~decisions ~request with
       | Error m -> Printf.eprintf "[k4kspec] agent backend unusable after retries:\n%s\n" m; exit 5
       | Ok d ->
           let against =
             match Sign.verify file with
             | Sign.Valid (s, _) -> Printf.sprintf "v%d" s.Sign.version
             | _ -> "unsigned"
           in
           let record : Record.t =
             { Record.fields =
                 [ ("k4k-proposal", "1"); ("kind", "revise"); ("spec", Filename.basename file);
                   ("against-version", against); ("against-sha256", Sign.hash_bytes spec);
                   ("date", Store.timestamp ()); ("backend", d.Propose.backend_name);
                   ("proposal-check", if d.Propose.check_ok then "parses, check=pass" else "parses, check=FAIL") ];
               sections =
                 [ ("decisions", d.Propose.decisions_text); ("proposed spec", d.Propose.spec_text);
                   ("proposed hints", d.Propose.hints_text) ] }
           in
           Store.write_new (Store.proposal_path file "revise") (Record.to_string record);
           Store.write_file (Store.new_spec_path file) d.Propose.spec_text;
           Store.write_file (Store.new_hints_path file) d.Propose.hints_text;
           Store.write_file dpath d.Propose.decisions_text;
           (match d.Propose.summary_text with Some s -> Printf.printf "== the agent's summary ==\n%s\n" s | None -> ());
           print_endline "== mechanical delta (computed, not the agent's claim) ==";
           (match Parse.parse spec with
            | old_sp -> (match Parse.parse d.Propose.spec_text with
                         | new_sp -> print_string (Propose.mechanical_delta old_sp new_sp)
                         | exception _ -> ())
            | exception _ -> print_endline "  (current spec does not parse; no delta)");
           print_endline "== line diff (current -> proposed) ==";
           print_string (Propose.line_diff spec d.Propose.spec_text);
           print_endline "== check on the proposed draft ==";
           print_string d.Propose.check_report;
           (match Sign.verify file with
            | Sign.Valid (s, _) ->
                Printf.printf "\nNOTE: %s is SIGNED (v%d); accepting this draft invalidates the signature —\n\
                               review, `mv %s %s`, then re-sign.\n"
                  file s.Sign.version (Store.new_spec_path file) file
            | _ ->
                Printf.printf "\nreview, then accept with: mv %s %s\n" (Store.new_spec_path file) file);
           exit (if d.Propose.check_ok then 0 else 1))
  | _ :: "propose-fix" :: file :: _ ->
      if not (Sys.file_exists file) then (Printf.eprintf "[k4kspec] no such file: %s\n" file; exit 2);
      let fpath = Store.last_failure_path file in
      if not (Sys.file_exists fpath) then
        (Printf.eprintf "[k4kspec] REFUSE: no failure report (%s) — run certify-agent first.\n" fpath; exit 6);
      let spec = Store.read_file file in
      let hints_path = Store.hints_path file in
      let hints = if Sys.file_exists hints_path then Store.read_file hints_path else "" in
      let backend = Propose.authoring_backend ~stub:Propose.stub_revise_backend in
      (match Propose.propose_fix ~backend ~spec ~hints ~failure:(Store.read_file fpath) with
       | Error m -> Printf.eprintf "[k4kspec] agent backend unusable after retries:\n%s\n" m; exit 5
       | Ok d ->
           let record : Record.t =
             { Record.fields =
                 [ ("k4k-proposal", "1"); ("kind", "fix"); ("spec", Filename.basename file);
                   ("against-sha256", Sign.hash_bytes spec); ("date", Store.timestamp ());
                   ("backend", d.Propose.backend_name);
                   ("proposal-check", if d.Propose.check_ok then "parses, check=pass" else "parses, check=FAIL") ];
               sections =
                 [ ("decisions", d.Propose.decisions_text); ("proposed spec", d.Propose.spec_text);
                   ("proposed hints", d.Propose.hints_text) ] }
           in
           let ppath = Store.proposal_path file "fix" in
           Store.write_new ppath (Record.to_string record);
           Store.write_file (Store.new_spec_path file) d.Propose.spec_text;
           (match d.Propose.summary_text with Some s -> Printf.printf "== the agent's summary ==\n%s\n" s | None -> ());
           print_endline "== line diff (current -> proposed) ==";
           print_string (Propose.line_diff spec d.Propose.spec_text);
           Printf.printf "proposal: %s\nreview, then accept with: mv %s %s  (then re-sign and re-run certify-agent)\n"
             ppath (Store.new_spec_path file) file;
           exit (if d.Propose.check_ok then 0 else 1))
  | _ :: "sign" :: file :: rest ->
      let ack = List.mem "--ack-underspec" rest in
      let rec waivers acc = function
        | [] -> List.rev acc
        | "--ack-underspec" :: tl -> waivers acc tl
        | "--waive" :: wref :: "--rationale" :: text :: tl ->
            (match Sign.parse_waiver_ref wref with
             | Ok (i, j, t) -> waivers ((i, j, t, text) :: acc) tl
             | Error m -> Printf.eprintf "[k4kspec] %s\n" m; exit 2)
        | "--waive" :: _ ->
            Printf.eprintf "[k4kspec] --waive REF must be immediately followed by --rationale TEXT\n"; exit 2
        | a :: _ -> Printf.eprintf "[k4kspec] unknown argument to sign: %s\n" a; exit 2
      in
      let ws = waivers [] rest in
      (match Sign.sign ~spec_path:file ~ack_underspec:ack ~waivers:ws with
       | Ok (v, path) ->
           Printf.printf "signed: %s -> v%d  (%s)\n" file v path;
           if ws <> [] then
             Printf.printf "  %d law(s) WAIVED to tier B/C — they will NOT be formally verified;\n  the certificate will disclose this.\n" (List.length ws);
           exit 0
       | Error { Sign.msg; code } -> prerr_endline msg; exit code)
  | _ :: "status" :: file :: _ ->
      if not (Sys.file_exists file) then (Printf.eprintf "[k4kspec] no such file: %s\n" file; exit 2);
      (match Sign.verify file with
       | Sign.Valid (s, path) ->
           Printf.printf "signed: v%d  (%s)\n  spec sha256 %s\n  signer %s  date %s\n"
             s.Sign.version path s.Sign.spec_hash s.Sign.signer s.Sign.date;
           List.iter (fun u -> Printf.printf "  underspec: %s\n" u) s.Sign.underspec;
           List.iter (fun w -> Printf.printf "  WAIVED: case#%d.law#%d tier=%s (NOT formally verified)\n"
                         w.Sign.case_i w.Sign.law_j w.Sign.tier) s.Sign.waivers;
           let cdir = Store.certificates_dir file s.Sign.version in
           Printf.printf "certificate v%d: %s\n" s.Sign.version
             (if Sys.file_exists cdir then "present (" ^ cdir ^ ")" else "absent")
       | Sign.Unsigned -> print_endline "unsigned (no signature record)"
       | Sign.Mismatch m -> Printf.printf "STALE signature: %s\n" m);
      let pdir = Store.proposals_dir file in
      Printf.printf "proposals: %d\n" (if Sys.file_exists pdir then Array.length (Sys.readdir pdir) else 0);
      exit 0
  | _ :: "check" :: name :: rest -> do_check name rest
  | _ :: "run" :: name :: "--" :: args -> do_run name args
  | _ -> print_string usage; exit 2
