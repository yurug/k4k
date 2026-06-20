(* The certify driver: parse-> Rocq emit -> coqc -> extract -> compile (extracted core
   + I/O shim) -> run the binary -> cross-check vs the Eval oracle -> TCB manifest.
   v1: NO-FILE fragment. Returns a pass/fail report with a log. *)

open Ast

(* the trusted I/O shim, specialised to the footprint + extracted module name.
   It reads EXACTLY the declared footprint paths (frame by construction). *)
let shim_ml (sp : spec) : string =
  let m = String.capitalize_ascii (sp.name ^ "_ext") in
  let conv =
    "let to_cl (s : string) : char list = List.init (String.length s) (String.get s)\n\
     let of_cl (l : char list) : string = String.of_seq (List.to_seq l)\n\
     let read_opt p = (try let ic = open_in_bin p in let n = in_channel_length ic in\n\
    \    let s = really_input_string ic n in close_in ic; Some (to_cl s) with _ -> None)\n"
  in
  let emit_out = Printf.sprintf "  print_string (of_cl o.%s.stdout); prerr_string (of_cl o.%s.stderr); exit o.%s.exit\n" m m m in
  match sp.reads with
  | NoFiles ->
      conv ^ "let () =\n\
             \  let args = match Array.to_list Sys.argv with _ :: r -> r | [] -> [] in\n"
      ^ Printf.sprintf "  let o = %s.run (List.map to_cl args) in\n" m ^ emit_out
  | FileAt idx ->
      conv ^ "let () =\n\
             \  let args = match Array.to_list Sys.argv with _ :: r -> r | [] -> [] in\n"
      ^ Printf.sprintf "  let file1 = (match List.nth_opt args %d with Some p -> read_opt p | None -> None) in\n" idx
      ^ Printf.sprintf "  let o = %s.run { %s.argv = List.map to_cl args; %s.file1 = file1 } in\n" m m m ^ emit_out
  | FileAtEach ->
      conv ^ "let () =\n\
             \  let args = match Array.to_list Sys.argv with _ :: r -> r | [] -> [] in\n\
             \  let contents = List.map read_opt args in\n"
      ^ Printf.sprintf "  let o = %s.run { %s.argv = List.map to_cl args; %s.contents = contents } in\n" m m m ^ emit_out

type report = { ok : bool; log : string list }

(* lightweight INTERMEDIATE gate for the structured methodology (ADR-020): compile Kalgebra + the
   given .v, ADMITS ALLOWED (this is scaffolding — typecheck / skeleton / per-lemma checks, NOT a
   certificate; the certificate is only ever certify_v, which BANS admits). Returns (compiles?, output). *)
let coqc_check ?(workdir = "/tmp/k4k_coqc_check") (name : string) (v : string) : bool * string =
  let path f = Filename.concat workdir f in
  let write f s = let oc = open_out (path f) in output_string oc s; close_out oc in
  ignore (Sys.command (Printf.sprintf "rm -rf %s && mkdir -p %s" (Filename.quote workdir) (Filename.quote workdir)));
  match Refdiff.which "coqc" with
  | None -> (false, "coqc not on PATH")
  | Some coqc -> (
      match List.find_opt Sys.file_exists [ "k4kspec/backend/Kalgebra.v"; "backend/Kalgebra.v"; "../backend/Kalgebra.v" ] with
      | None -> (false, "cannot locate Kalgebra.v")
      | Some ksrc ->
          let ic = open_in_bin ksrc in let kn = in_channel_length ic in
          let ks = really_input_string ic kn in close_in ic; write "Kalgebra.v" ks;
          let ck, ko, ke = Refdiff.run_cmd [ coqc; "-Q"; "."; ""; "Kalgebra.v" ] ~cwd:workdir in
          if ck <> 0 then (false, Printf.sprintf "Kalgebra.v failed: %s%s" ko ke)
          else begin
            write (name ^ ".v") v;
            let c, o, e = Refdiff.run_cmd [ coqc; "-Q"; "."; ""; name ^ ".v" ] ~cwd:workdir in
            (c = 0, o ^ e)
          end)

(* the pipeline given a final .v source (elaborator- OR agent-produced): write it, gate on no
   escape hatches, coqc (with the audited-once Kalgebra), extract, compile (+ shim), run,
   cross-check vs the oracle, write the manifest. *)
let certify_v ?(workdir = "/tmp/k4k_certify") (sp : spec) (v : string) : report =
  let log = ref [] in
  let say s = log := s :: !log in
  let done_ ok = { ok; log = List.rev !log } in
  let path f = Filename.concat workdir f in
  let write f s = let oc = open_out (path f) in output_string oc s; close_out oc in
  ignore (Sys.command (Printf.sprintf "rm -rf %s && mkdir -p %s" (Filename.quote workdir) (Filename.quote workdir)));
  let name = sp.name in
  write (name ^ ".v") v;
  (* honesty gate: no escape hatches in the proof *)
  let banned = List.filter (fun w -> Algebra.contains v w) [ "Admitted"; "Axiom "; " admit"; "admit."; "give_up"; "Parameter "; "Conjecture"; "Abort" ] in
       if banned <> [] then (say ("FAIL: generated .v contains banned: " ^ String.concat ", " banned); done_ false)
       else begin
         match Refdiff.which "coqc", Refdiff.which "ocamlfind" with
         | None, _ -> say "FAIL: coqc not on PATH"; done_ false
         | _, None -> say "FAIL: ocamlfind not on PATH"; done_ false
         | Some coqc, Some ocf ->
             (* audited-once blessed algebra: copy backend/Kalgebra.v in and compile it first *)
             let kalg_ok =
               match List.find_opt Sys.file_exists [ "k4kspec/backend/Kalgebra.v"; "backend/Kalgebra.v"; "../backend/Kalgebra.v" ] with
               | None -> say "FAIL: cannot locate k4kspec/backend/Kalgebra.v"; false
               | Some ksrc ->
                   let ic = open_in_bin ksrc in let kn = in_channel_length ic in
                   let ks = really_input_string ic kn in close_in ic; write "Kalgebra.v" ks;
                   let ck, ko, ke = Refdiff.run_cmd [ coqc; "-Q"; "."; ""; "Kalgebra.v" ] ~cwd:workdir in
                   if ck <> 0 then (say (Printf.sprintf "FAIL: coqc Kalgebra.v exit %d:\n%s%s" ck ko ke); false) else true
             in
             if not kalg_ok then done_ false
             else
             (* 2. coqc checks the proof + extracts (the generated .v requires Kalgebra) *)
             let c1, o1, e1 = Refdiff.run_cmd [ coqc; "-Q"; "."; ""; name ^ ".v" ] ~cwd:workdir in
             if c1 <> 0 then (say (Printf.sprintf "FAIL: coqc exit %d:\n%s%s" c1 o1 e1); done_ false)
             else begin
               say "coqc: proof CHECKED (exit 0; algebra from audited-once Kalgebra.v), extraction done";
               (* 3. shim + compile the certified binary *)
               write (name ^ "_main.ml") (shim_ml sp);
               let c2, o2, e2 = Refdiff.run_cmd [ ocf; "ocamlopt"; name ^ "_ext.mli"; name ^ "_ext.ml"; name ^ "_main.ml"; "-o"; name ] ~cwd:workdir in
               if c2 <> 0 then (say (Printf.sprintf "FAIL: ocamlopt exit %d:\n%s%s" c2 o2 e2); done_ false)
               else begin
                 say "compiled the certified binary";
                 (* 4. cross-check binary vs the Eval oracle on examples + sweep *)
                 let bin = path name in
                 let inputs = List.map (fun e -> (e.ex_argv, e.ex_files)) sp.examples @ Check.scenarios sp in
                 let mism = ref 0 and prev = ref [] and checked = ref 0 in
                 List.iter
                   (fun (argv, files) ->
                     (* materialise exactly this input's files on disk; the binary reads them *)
                     List.iter (fun (p, _) -> (try Sys.remove (path p) with _ -> ())) !prev;
                     List.iter (fun (p, c) -> write p c) files;
                     prev := files;
                     let oracle = try Some (Eval.run sp (Eval.input_of argv files)) with Eval.Spec_error _ -> None in
                     match oracle with
                     | None -> ()   (* under-determined input (e.g. relational-law output): proof-guaranteed, not cross-checked *)
                     | Some o ->
                         incr checked;
                         let bc, bout, _ = Refdiff.run_cmd (bin :: argv) ~cwd:workdir in
                         if bout <> o.Eval.rstdout || bc <> o.Eval.rexit then begin
                           incr mism;
                           if !mism <= 5 then
                             say (Printf.sprintf "MISMATCH argv=[%s] files=[%s]: binary(out=%S exit=%d) vs spec(out=%S exit=%d)"
                                    (String.concat ";" argv) (String.concat ";" (List.map fst files)) bout bc o.Eval.rstdout o.Eval.rexit)
                         end)
                   inputs;
                 List.iter (fun (p, _) -> (try Sys.remove (path p) with _ -> ())) !prev;
                 if !mism > 0 then (say (Printf.sprintf "FAIL: %d binary/spec mismatch(es)" !mism); done_ false)
                 else begin
                   let skipped = List.length inputs - !checked in
                   say (Printf.sprintf "binary MATCHES spec on %d/%d inputs%s" !checked (List.length inputs)
                          (if skipped > 0 then Printf.sprintf " (%d under-determined: output is proof-guaranteed, not cross-checked)" skipped else ""));
                   (* 5. TCB manifest *)
                   let _, coqv, _ = Refdiff.run_cmd [ coqc; "--version" ] ~cwd:workdir in
                   let manifest =
                     Printf.sprintf
                       "# TCB manifest — %s\n\nClaim: the extracted implementation is PROVEN (coqc) to satisfy spec_rel,\nthe relation denoted by the signed k4kspec, MODULO this trusted base:\n\n- Rocq kernel + extraction: %s- OCaml compiler (ocamlfind ocamlopt %s)\n- the blessed value algebra (audited-once backend/Kalgebra.v; extracted into %s_ext.ml)\n- the I/O shim (%s_main.ml)\n- the elaborator (lib/rocq_emit.ml)\n\nArtifacts: %s.v (source+proof), %s_ext.ml (extracted), %s (binary).\nLimitation: v1 generates `run` to match the spec, so the proof is easy; replacing the\ndeterministic generator with a stochastic agent backend (hard proofs) is future work.\n"
                       name coqv (match Refdiff.which "ocamlopt" with Some p -> p | None -> "ocamlopt") name name name name name
                   in
                   write (name ^ ".tcb.md") manifest;
                   say (Printf.sprintf "wrote %s.tcb.md ; certified binary at %s" name bin);
                   done_ true
                 end
               end
             end
       end

(* the deterministic v1 path: the elaborator generates run + a generic proof *)
let certify ?(workdir = "/tmp/k4k_certify") (sp : spec) : report =
  match (try `Ok (Rocq_emit.emit sp) with Failure m -> `Err m) with
  | `Err m -> { ok = false; log = [ "FAIL: elaboration: " ^ m ] }
  | `Ok v -> certify_v ~workdir sp v
