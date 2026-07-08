(* The AGENT PROOF backend (the central bet): instead of the elaborator generating `run` to
   match the spec, an external agent proposes an implementation `run` + a Coq proof of
   `forall i, spec_rel i (run i)`, and coqc is the ONLY gate (accept iff coqc closes the proof
   with no escape hatches). On a coqc failure the error is fed back and the agent retries
   (propose / reject-with-diagnostic). This is the harness's propose/accept-or-reject pattern
   lifted to the proof level. The certified statement `spec_rel` is fixed by the elaborator;
   the agent only supplies `run` + the proof, so it cannot weaken what is certified. *)

open Ast

type backend = { name : string; invoke : string -> string }   (* prompt -> raw response *)

(* ---- run an external command with the prompt on stdin, capture stdout -------- *)
let run_with_stdin (cmd : string) (input : string) : int * string * string =
  let inf = Filename.temp_file "k4k_in" "" and outf = Filename.temp_file "k4k_out" "" and errf = Filename.temp_file "k4k_err" "" in
  (let oc = open_out_bin inf in output_string oc input; close_out oc);
  let fi = Unix.openfile inf [ O_RDONLY ] 0 in
  let fo = Unix.openfile outf [ O_WRONLY; O_TRUNC ] 0o600 in
  let fe = Unix.openfile errf [ O_WRONLY; O_TRUNC ] 0o600 in
  let pid = Unix.create_process "/bin/sh" [| "/bin/sh"; "-c"; cmd |] fi fo fe in
  List.iter Unix.close [ fi; fo; fe ];
  let _, st = Unix.waitpid [] pid in
  let code = match st with Unix.WEXITED c -> c | WSIGNALED s | WSTOPPED s -> 128 + s in
  let read f = let ic = open_in_bin f in let n = in_channel_length ic in let s = really_input_string ic n in close_in ic; (try Sys.remove f with _ -> ()); s in
  (try Sys.remove inf with _ -> ());
  (code, read outf, read errf)

(* external backend from $K4K_PROOF_CMD (reads the prompt on stdin, prints raw Coq on stdout) *)
let external_backend (cmd : string) : backend =
  { name = "external:" ^ cmd; invoke = (fun p -> let _, out, _ = run_with_stdin cmd p in out) }

(* deterministic stub: returns the elaborator's own run+proof (always closes coqc) — exercises
   the harness plumbing without an LLM. *)
let stub_backend (sp : spec) : backend =
  { name = "stub"; invoke = (fun _ -> Rocq_emit.emit_impl sp) }

(* ---- response cleaning: extract the Coq from fenced OR prose-wrapped output ---- *)
let clean (resp : string) : string =
  let s = String.trim resp in
  let lines = String.split_on_char '\n' s in
  let is_fence l = let t = String.trim l in String.length t >= 3 && String.sub t 0 3 = "```" in
  if List.exists is_fence lines then begin
    (* fenced: keep the text inside ``` fences *)
    let rec collect acc inside = function
      | [] -> List.rev acc
      | l :: rest ->
          if is_fence l then collect acc (not inside) rest
          else if inside then collect (l :: acc) inside rest
          else collect acc inside rest
    in
    let body = collect [] false lines in
    if body = [] then s else String.concat "\n" body
  end
  else begin
    (* unfenced: drop leading prose up to the first Coq vernac, and trailing prose after the last Qed/Defined *)
    let starts_with t k = String.length t >= String.length k && String.sub t 0 (String.length k) = k in
    let starts_coq l =
      let t = String.trim l in
      List.exists (starts_with t) [ "Require"; "Definition"; "Fixpoint"; "Lemma"; "Theorem"; "Inductive"; "Notation"; "Import"; "Section"; "Local"; "Hint"; "Instance" ]
    in
    let ends_proof l = let t = String.trim l in t = "Qed." || t = "Defined." in
    let rec drop_lead = function l :: rest when not (starts_coq l) -> drop_lead rest | ls -> ls in
    let rec drop_tail = function l :: rest when not (ends_proof l) -> drop_tail rest | ls -> ls in
    String.concat "\n" (List.rev (drop_tail (List.rev (drop_lead lines))))
  end

(* ---- the prompt ----------------------------------------------------------- *)
let base_prompt (stmt : string) : string =
  "You are completing a Coq (Rocq 9.1) development. The following is ALREADY defined and compiled;\n\
   do NOT redefine any of it. The module `Kalgebra` is imported and provides: `bytes` (= string),\n\
   `Output` (a record { stdout : bytes; stderr : bytes; exit : nat }), and total helpers\n\
   `ascii_upper` `ascii_lower` `bnth` (nth of a list bytes, default \"\") `fbytes` (option bytes -> bytes)\n\
   `one_nonempty_line` (s <> \"\") `lines` `unlines` `splits` (split on a 1-byte delimiter) `contains`\n\
   `lfirst` `is_decimal` `int_of`, plus the Coq stdlib (String, List, Nat, Bool: length, nth, append,\n\
   Nat.eqb, Nat.ltb, Nat.leb, negb, andb, existsb, List.filter, List.map, fold_left, etc.).\n\n\
   The Input type and the specification relation are:\n\n" ^ stmt ^ "\n\n\
   Provide EXACTLY these two items and NOTHING ELSE (no prose, no Require, no Import, no markdown):\n\n\
   Definition run (i : Input) : Output := (* your implementation *).\n\n\
   Theorem correct : forall i, spec_rel i (run i).\n\
   Proof.\n\
   (* your proof *)\n\
   Qed.\n\n\
   Rules: use ONLY Kalgebra + Coq stdlib; do NOT use Admitted, Axiom, admit, Parameter, Conjecture,\n\
   or Abort; the proof MUST close with Qed. Output raw Coq text only."

let retry_suffix (coqc_log : string) : string =
  "\n\nYour previous attempt did NOT compile. coqc reported:\n" ^ coqc_log
  ^ "\nReturn corrected `run` and `correct` (the two items only)."

(* ---- the harness ---------------------------------------------------------- *)
let certify ?(workdir = "/tmp/k4k_certify_agent") ?(max_attempts = 4) ~(backend : backend) (sp : spec) : Certify.report =
  let stmt = (try Rocq_emit.emit_statement sp with Failure m -> failwith ("statement: " ^ m)) in
  let extr = Rocq_emit.extraction_for sp.name in
  let base = base_prompt stmt in
  let assemble body = String.concat "\n" [ stmt; body; extr ] in
  let rec loop attempt prompt acc_log =
    let body = clean (backend.invoke prompt) in
    let v = assemble body in
    let r = Certify.certify_v ~workdir ~limitation:Certify.agent_provenance sp v in
    let attempt_log = Printf.sprintf "[attempt %d via %s] %s" attempt backend.name (if r.Certify.ok then "coqc CLOSED the agent's proof; certified" else "rejected") in
    if r.Certify.ok then { Certify.ok = true; log = acc_log @ [ attempt_log ] @ r.Certify.log }
    else if attempt >= max_attempts then
      { Certify.ok = false; log = acc_log @ [ attempt_log ] @ r.Certify.log @ [ Printf.sprintf "agent proof FAILED after %d attempts" attempt ] }
    else loop (attempt + 1) (base ^ retry_suffix (String.concat "\n" r.Certify.log)) (acc_log @ [ attempt_log ])
  in
  loop 1 base []

(* ===== STRUCTURED METHODOLOGY (ADR-020): implement-naive -> sketch -> fill -> assemble ======== *)

let kalgebra_blurb =
  "The module `Kalgebra` is imported and provides: `bytes`(=string), `Output`{stdout;stderr;exit:nat},\n\
   helpers `ascii_upper` `ascii_lower` `bnth` `fbytes` `one_nonempty_line` `lines` `unlines` `splits`\n\
   `contains` `lfirst` `is_decimal` `int_of`; order relations `ascii_le` `ascii_lt` `part_le`; and (for\n\
   relational laws) `Sorted`/`Permutation` (Coq.Sorting), `list_ascii_of_string`/`string_of_list_ascii`\n\
   (+ the roundtrip lemma `list_ascii_of_string_of_list_ascii`), plus the Coq stdlib (String, List, Nat,\n\
   Bool, Sorting; `List.filter`, `List.nodup`, `Ascii.ascii_dec`, `StronglySorted`, etc.)."

let impl_prompt stmt =
  "You are writing a CERTIFIED Coq (Rocq 9.1) implementation by a STRUCTURED method.\n" ^ kalgebra_blurb
  ^ "\n\nThe Input type and the specification relation are ALREADY defined (do NOT restate them):\n\n"
  ^ stmt
  ^ "\n\nSTEP 1 of 3 — IMPLEMENT. Give ONLY the implementation, as the SIMPLEST, most OBVIOUSLY-CORRECT\n\
     `run` — the one whose correctness proof will be SHORTEST. Favor naive clarity over efficiency\n\
     (reuse stdlib: insertion sort, `List.filter`, `List.nodup Ascii.ascii_dec`, etc.). Output EXACTLY\n\
     one item, raw Coq, NO prose, NO Require:\n\n\
     Definition run (i : Input) : Output := (* naive, obviously correct *)."

let sketch_prompt stmt run =
  "You are proving a CERTIFIED Coq theorem by a STRUCTURED method.\n" ^ kalgebra_blurb
  ^ "\n\nAlready defined (do NOT restate `Input`, `spec_rel`, or `run`):\n\n" ^ stmt ^ "\n\n" ^ run
  ^ "\n\nSTEP 2 of 3 — SKETCH the proof. DECOMPOSE `correct : forall i, spec_rel i (run i)` into named\n\
     HELPER LEMMAS — one per non-trivial obligation (e.g. for each relational law: a sortedness lemma,\n\
     a permutation/membership lemma) — and write the TOP-LEVEL proof of `correct` that USES them.\n\
     You MAY leave any helper lemma you have not yet proved as `Admitted`, BUT THE WHOLE THING MUST\n\
     COMPILE: the lemma STATEMENTS must be right and `correct` must go through GIVEN the lemmas.\n\
     Output raw Coq only — the helper `Lemma`s (each `Lemma name : <stmt>. Proof. ... Admitted.`, or a\n\
     real proof if trivial) then `Theorem correct : forall i, spec_rel i (run i). Proof. ... Qed.` No prose."

let fill_prompt stmt run dev =
  "You are completing a CERTIFIED Coq proof by a STRUCTURED method.\n" ^ kalgebra_blurb
  ^ "\n\nAlready defined (do NOT restate `Input`, `spec_rel`, or `run`):\n\n" ^ stmt ^ "\n\n" ^ run
  ^ "\n\nThe proof so far (helper lemmas + `correct`), which COMPILES but still contains `Admitted`:\n\n"
  ^ dev
  ^ "\n\nSTEP 3 of 3 — FILL. Replace EVERY `Admitted`/`admit` with a real proof ending in `Qed.` (you may\n\
     add more helper lemmas). Return the COMPLETE development — all helper lemmas + `Theorem correct\n\
     ... Qed.` — raw Coq only, with NO `Admitted`/`admit`/`Axiom` remaining. Do NOT restate run/spec_rel/Input."

let has_admit v = List.exists (Algebra.contains v) [ "Admitted"; " admit"; "admit."; "Abort"; "Axiom" ]

(* the structured harness: each step is coqc-gated (intermediate gates allow admits; the FINAL gate,
   certify_v, bans them). The skeleton gate (PHASE 2) kernel-checks the decomposition before any
   hard lemma is proved. *)
let certify_structured ?(workdir = "/tmp/k4k_certify_agent") ?(max_attempts = 3) ?(max_fill = 4) ~(backend : backend) (sp : spec) : Certify.report =
  let stmt = (try Rocq_emit.emit_statement sp with Failure m -> failwith ("statement: " ^ m)) in
  let extr = Rocq_emit.extraction_for sp.Ast.name in
  let name = sp.Ast.name in
  let chk = workdir ^ "_chk" in
  let log = ref [] in
  let say s = log := s :: !log; Printf.eprintf "%s\n%!" s in   (* live progress + accumulate *)
  let fail () = { Certify.ok = false; log = List.rev !log } in
  let check v = Certify.coqc_check ~workdir:chk name v in
  (* PHASE 1 — IMPLEMENT (naive); gate: run typechecks against the goal *)
  let rec p1 attempt prompt =
    say (Printf.sprintf "[impl] attempt %d: requesting a naive implementation..." attempt);
    let run = clean (backend.invoke prompt) in
    let ok, out = check (String.concat "\n" [ stmt; run; "Definition _goal : Prop := forall i, spec_rel i (run i)." ]) in
    if ok then (say (Printf.sprintf "[impl] naive run typechecks (attempt %d)" attempt); Some run)
    else if attempt >= max_attempts then (say (Printf.sprintf "[impl] FAILED after %d attempts:\n%s" attempt out); None)
    else p1 (attempt + 1) (impl_prompt stmt ^ "\n\nYour previous `run` did not typecheck. coqc said:\n" ^ out ^ "\nReturn a corrected `Definition run` only.")
  in
  (match p1 1 (impl_prompt stmt) with
   | None -> fail ()
   | Some run ->
     (* PHASE 2 — SKETCH (the skeleton gate): admits allowed, must compile and define `correct` *)
     let rec p2 attempt prompt =
       say (Printf.sprintf "[sketch] attempt %d: requesting the proof skeleton (lemmas may be Admitted)..." attempt);
       let dev = clean (backend.invoke prompt) in
       let ok, out = check (String.concat "\n" [ stmt; run; dev ]) in
       if ok && Algebra.contains dev "correct" then
         (say (Printf.sprintf "[sketch] SKELETON GATE passed (attempt %d): decomposition type-correct & sufficient (coqc accepts modulo Admitted)" attempt); Some dev)
       else if attempt >= max_attempts then (say (Printf.sprintf "[sketch] FAILED after %d attempts:\n%s" attempt out); None)
       else p2 (attempt + 1) (sketch_prompt stmt run ^ "\n\nYour previous skeleton failed the gate. coqc said:\n" ^ out ^ "\nReturn corrected helper lemmas + `correct` (lemmas may remain Admitted).")
     in
     (match p2 1 (sketch_prompt stmt run) with
      | None -> fail ()
      | Some dev0 ->
        (* PHASE 3 — FILL: drive admits -> 0 while staying compiled *)
        let rec p3 round dev =
          if not (has_admit dev) then (say (Printf.sprintf "[fill] all lemmas proved (after %d round(s))" (round - 1)); Some dev)
          else if round > max_fill then (say (Printf.sprintf "[fill] admits REMAIN after %d rounds — final gate will reject honestly" max_fill); Some dev)
          else
            let rec one k prompt =
              say (Printf.sprintf "[fill round %d] sub-attempt %d: proving the Admitted lemmas..." round k);
              let body = clean (backend.invoke prompt) in
              let ok, out = check (String.concat "\n" [ stmt; run; body ]) in
              if ok then Some body
              else if k >= 2 then (say (Printf.sprintf "[fill round %d] could not get a compiling development; coqc:\n%s" round out); None)
              else one (k + 1) (fill_prompt stmt run dev ^ "\n\nYour previous fill did NOT compile. coqc said:\n" ^ out ^ "\nReturn the complete development again, corrected.")
            in
            (match one 1 (fill_prompt stmt run dev) with
             | Some body -> say (Printf.sprintf "[fill round %d] compiles (admits left: %b)" round (has_admit body)); p3 (round + 1) body
             | None -> Some dev)
        in
        (match p3 1 dev0 with
         | None -> fail ()
         | Some devf ->
           say "[assemble] FINAL gate: certify_v (bans admits; coqc; extract; compile; cross-check; manifest)";
           let r = Certify.certify_v ~workdir ~limitation:Certify.agent_provenance sp (String.concat "\n" [ stmt; run; devf; extr ]) in
           { Certify.ok = r.Certify.ok; log = List.rev !log @ r.Certify.log })))

(* ===== COMPOSITIONAL METHODOLOGY (ADR-021): decompose -> module-interface gate -> certify each
   component -> assemble. The agent proposes COMPONENTS (impl + functional contract), `run` as their
   composition, and a glue proof of the top spec from the component contracts; the harness gates the
   decomposition (the glue must be Qed'd with the component certificates Admitted) and then drives
   the component certificates to proven. Generalizes ADR-020's skeleton gate to a module boundary. *)

let decompose_prompt stmt =
  "You are building a CERTIFIED Coq (Rocq 9.1) program by COMPOSITIONAL decomposition.\n" ^ kalgebra_blurb
  ^ "\n\nThe Input type and the specification relation are ALREADY defined (do NOT restate them):\n\n" ^ stmt
  ^ "\n\nDECOMPOSE the implementation into COMPONENTS and prove the top goal FROM THEIR CONTRACTS:\n\
     1. Define each component as a Coq function `Definition compK (x : AK) : BK := ...` (naive/clear).\n\
     2. Give each a CONTRACT `Definition compK_spec (x : AK) (y : BK) : Prop := ...`.\n\
     3. Define `run : Input -> Output` as the COMPOSITION of the components.\n\
     4. State each component certificate `Lemma compK_correct : forall x, compK_spec x (compK x).`\n\
        and leave its proof `Admitted` FOR NOW.\n\
     5. PROVE the top `Theorem correct : forall i, spec_rel i (run i).` with a real `Qed`, using ONLY\n\
        the `compK_correct` lemmas (the GLUE). The WHOLE thing MUST COMPILE: the glue must go through\n\
        GIVEN the Admitted component certificates (this is the module-interface gate).\n\
     Output raw Coq only — component `Definition`s + `_spec`s, `run`, the Admitted `compK_correct`\n\
     lemmas, then `Theorem correct ... Qed.` Do NOT restate Input/spec_rel. No prose."

let fill_comp_prompt stmt dev =
  "You are completing a CERTIFIED Coq program (compositional).\n" ^ kalgebra_blurb
  ^ "\n\nAlready defined (do NOT restate Input/spec_rel):\n\n" ^ stmt
  ^ "\n\nThe development so far (components + `run` + the glue `correct`), which COMPILES but whose\n\
     component certificates are still `Admitted`:\n\n" ^ dev
  ^ "\n\nProve EVERY Admitted `compK_correct` (you may add helper lemmas above each). Return the COMPLETE\n\
     development — all component `Definition`s/`_spec`s, `run`, every `compK_correct` (now real `Qed`),\n\
     and `Theorem correct ... Qed.` — raw Coq only, with NO `Admitted`/`admit`/`Axiom`. Don't restate Input/spec_rel."

let certify_compositional ?(workdir = "/tmp/k4k_certify_agent") ?(max_attempts = 3) ?(max_fill = 5) ~(backend : backend) (sp : spec) : Certify.report =
  let stmt = (try Rocq_emit.emit_statement sp with Failure m -> failwith ("statement: " ^ m)) in
  let extr = Rocq_emit.extraction_for sp.Ast.name in
  let name = sp.Ast.name in
  let chk = workdir ^ "_chk" in
  let log = ref [] in
  let say s = log := s :: !log; Printf.eprintf "%s\n%!" s in
  let fail () = { Certify.ok = false; log = List.rev !log } in
  let check v = Certify.coqc_check ~workdir:chk name v in
  (* PHASE A — DECOMPOSE + MODULE-INTERFACE GATE *)
  let rec decompose attempt prompt =
    say (Printf.sprintf "[decompose] attempt %d: requesting components + contracts + run + glue (certs Admitted)..." attempt);
    let dev = clean (backend.invoke prompt) in
    let ok, out = check (String.concat "\n" [ stmt; dev ]) in
    if ok && Algebra.contains dev "correct" then
      (say (Printf.sprintf "[decompose] MODULE-INTERFACE GATE passed (attempt %d): run composes from the component contracts; glue Qed'd with components Admitted" attempt); Some dev)
    else if attempt >= max_attempts then (say (Printf.sprintf "[decompose] FAILED after %d attempts:\n%s" attempt out); None)
    else decompose (attempt + 1) (decompose_prompt stmt ^ "\n\nYour previous decomposition failed the gate. coqc said:\n" ^ out ^ "\nReturn corrected components + run + Admitted certs + a Qed'd `correct`.")
  in
  (match decompose 1 (decompose_prompt stmt) with
   | None -> fail ()
   | Some dev0 ->
     (* PHASE B — CERTIFY EACH COMPONENT (drive the compK_correct admits to 0) *)
     let rec p_fill round dev =
       if not (has_admit dev) then (say (Printf.sprintf "[components] all component certificates proved (after %d round(s))" (round - 1)); Some dev)
       else if round > max_fill then (say (Printf.sprintf "[components] admits REMAIN after %d rounds — final gate will reject honestly" max_fill); Some dev)
       else
         let rec one k prompt =
           say (Printf.sprintf "[components round %d] sub-attempt %d: proving component certificates..." round k);
           let body = clean (backend.invoke prompt) in
           let ok, out = check (String.concat "\n" [ stmt; body ]) in
           if ok then Some body
           else if k >= 2 then (say (Printf.sprintf "[components round %d] no compiling development; coqc:\n%s" round out); None)
           else one (k + 1) (fill_comp_prompt stmt dev ^ "\n\nYour previous attempt did NOT compile. coqc said:\n" ^ out ^ "\nReturn the complete development again, corrected.")
         in
         (match one 1 (fill_comp_prompt stmt dev) with
          | Some body -> say (Printf.sprintf "[components round %d] compiles (admits left: %b)" round (has_admit body)); p_fill (round + 1) body
          | None -> Some dev)
     in
     (match p_fill 1 dev0 with
      | None -> fail ()
      | Some devf ->
        say "[assemble] FINAL gate: certify_v (bans admits; coqc; extract; compile; cross-check; manifest)";
        let r = Certify.certify_v ~workdir ~limitation:Certify.agent_provenance sp (String.concat "\n" [ stmt; devf; extr ]) in
        { Certify.ok = r.Certify.ok; log = List.rev !log @ r.Certify.log }))
