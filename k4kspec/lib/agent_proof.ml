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
    let r = Certify.certify_v ~workdir sp v in
    let attempt_log = Printf.sprintf "[attempt %d via %s] %s" attempt backend.name (if r.Certify.ok then "coqc CLOSED the agent's proof; certified" else "rejected") in
    if r.Certify.ok then { Certify.ok = true; log = acc_log @ [ attempt_log ] @ r.Certify.log }
    else if attempt >= max_attempts then
      { Certify.ok = false; log = acc_log @ [ attempt_log ] @ r.Certify.log @ [ Printf.sprintf "agent proof FAILED after %d attempts" attempt ] }
    else loop (attempt + 1) (base ^ retry_suffix (String.concat "\n" r.Certify.log)) (acc_log @ [ attempt_log ])
  in
  loop 1 base []
