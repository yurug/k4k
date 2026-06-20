(* The certify driver: parse-> Rocq emit -> coqc -> extract -> compile (extracted core
   + I/O shim) -> run the binary -> cross-check vs the Eval oracle -> TCB manifest.
   v1: NO-FILE fragment. Returns a pass/fail report with a log. *)

open Ast

(* the trusted no-file I/O shim, specialised to the extracted module name *)
let shim_ml (name : string) : string =
  let m = String.capitalize_ascii (name ^ "_ext") in
  Printf.sprintf
    "let to_cl (s : string) : char list = List.init (String.length s) (String.get s)\n\
     let of_cl (l : char list) : string = String.of_seq (List.to_seq l)\n\
     let () =\n\
    \  let args = match Array.to_list Sys.argv with _ :: r -> r | [] -> [] in\n\
    \  let o = %s.run (List.map to_cl args) in\n\
    \  print_string (of_cl o.%s.stdout);\n\
    \  prerr_string (of_cl o.%s.stderr);\n\
    \  exit o.%s.exit\n" m m m m

type report = { ok : bool; log : string list }

let certify ?(workdir = "/tmp/k4k_certify") (sp : spec) : report =
  let log = ref [] in
  let say s = log := s :: !log in
  let done_ ok = { ok; log = List.rev !log } in
  let path f = Filename.concat workdir f in
  let write f s = let oc = open_out (path f) in output_string oc s; close_out oc in
  ignore (Sys.command (Printf.sprintf "rm -rf %s && mkdir -p %s" (Filename.quote workdir) (Filename.quote workdir)));
  let name = sp.name in
  (* 1. emit the Rocq .v *)
  (match (try `Ok (Rocq_emit.emit sp) with Failure m -> `Err m) with
   | `Err m -> say ("FAIL: elaboration: " ^ m); done_ false
   | `Ok v ->
       write (name ^ ".v") v;
       (* honesty gate: no escape hatches in the generated proof *)
       let banned = List.filter (fun w -> Algebra.contains v w) [ "Admitted"; "Axiom "; " admit"; "Parameter "; "Conjecture" ] in
       if banned <> [] then (say ("FAIL: generated .v contains banned: " ^ String.concat ", " banned); done_ false)
       else begin
         match Refdiff.which "coqc", Refdiff.which "ocamlfind" with
         | None, _ -> say "FAIL: coqc not on PATH"; done_ false
         | _, None -> say "FAIL: ocamlfind not on PATH"; done_ false
         | Some coqc, Some ocf ->
             (* 2. coqc checks the proof + extracts *)
             let c1, o1, e1 = Refdiff.run_cmd [ coqc; name ^ ".v" ] ~cwd:workdir in
             if c1 <> 0 then (say (Printf.sprintf "FAIL: coqc exit %d:\n%s%s" c1 o1 e1); done_ false)
             else begin
               say "coqc: proof CHECKED (exit 0), extraction done";
               (* 3. shim + compile the certified binary *)
               write (name ^ "_main.ml") (shim_ml name);
               let c2, o2, e2 = Refdiff.run_cmd [ ocf; "ocamlopt"; name ^ "_ext.mli"; name ^ "_ext.ml"; name ^ "_main.ml"; "-o"; name ] ~cwd:workdir in
               if c2 <> 0 then (say (Printf.sprintf "FAIL: ocamlopt exit %d:\n%s%s" c2 o2 e2); done_ false)
               else begin
                 say "compiled the certified binary";
                 (* 4. cross-check binary vs the Eval oracle on examples + sweep *)
                 let bin = path name in
                 let inputs = List.map (fun e -> (e.ex_argv, e.ex_files)) sp.examples @ Check.scenarios sp in
                 let mism = ref 0 in
                 List.iter
                   (fun (argv, files) ->
                     let oracle = try Some (Eval.run sp (Eval.input_of argv files)) with Eval.Spec_error _ -> None in
                     match oracle with
                     | None -> ()
                     | Some o ->
                         let bc, bout, _ = Refdiff.run_cmd (bin :: argv) ~cwd:workdir in
                         if bout <> o.Eval.rstdout || bc <> o.Eval.rexit then begin
                           incr mism;
                           if !mism <= 5 then
                             say (Printf.sprintf "MISMATCH argv=[%s]: binary(out=%S exit=%d) vs spec(out=%S exit=%d)"
                                    (String.concat ";" argv) bout bc o.Eval.rstdout o.Eval.rexit)
                         end)
                   inputs;
                 if !mism > 0 then (say (Printf.sprintf "FAIL: %d binary/spec mismatch(es)" !mism); done_ false)
                 else begin
                   say (Printf.sprintf "binary MATCHES spec on %d inputs" (List.length inputs));
                   (* 5. TCB manifest *)
                   let _, coqv, _ = Refdiff.run_cmd [ coqc; "--version" ] ~cwd:workdir in
                   let manifest =
                     Printf.sprintf
                       "# TCB manifest — %s\n\nClaim: the extracted implementation is PROVEN (coqc) to satisfy spec_rel,\nthe relation denoted by the signed k4kspec, MODULO this trusted base:\n\n- Rocq kernel + extraction: %s- OCaml compiler (ocamlfind ocamlopt %s)\n- the blessed value algebra (Rocq preamble in %s.v)\n- the I/O shim (%s_main.ml)\n- the elaborator (lib/rocq_emit.ml)\n\nArtifacts: %s.v (source+proof), %s_ext.ml (extracted), %s (binary).\nLimitation: v1 generates `run` to match the spec, so the proof is easy; replacing the\ndeterministic generator with a stochastic agent backend (hard proofs) is future work.\n"
                       name coqv (match Refdiff.which "ocamlopt" with Some p -> p | None -> "ocamlopt") name name name name name
                   in
                   write (name ^ ".tcb.md") manifest;
                   say (Printf.sprintf "wrote %s.tcb.md ; certified binary at %s" name bin);
                   done_ true
                 end
               end
             end
       end)
