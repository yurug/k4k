open K4kspec

let usage =
  "k4kspec — reference-free spec-validation harness (v1 WIP)\n\n\
   usage:\n\
  \  k4kspec list                       list the built-in specs\n\
  \  k4kspec check <name>               validate a spec (examples + stability +\n\
  \                                     under-spec report + adversarial sweep)\n\
  \  k4kspec check <name> --ref '<cmd>' also run the OPTIONAL clone differential\n\
  \  k4kspec run   <name> -- <args...>  execute the spec as its own model\n\n\
   built-in specs: " ^ String.concat ", " (List.map fst Specs.by_name) ^ "\n"

let read_file_opt p =
  try let ic = open_in_bin p in let n = in_channel_length ic in
    let s = really_input_string ic n in close_in ic; Some s
  with _ -> None

let do_check name rest =
  match List.assoc_opt name Specs.by_name with
  | None -> Printf.eprintf "unknown spec: %s\n" name; exit 2
  | Some sp ->
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

let do_run name args =
  match List.assoc_opt name Specs.by_name with
  | None -> Printf.eprintf "unknown spec: %s\n" name; exit 2
  | Some sp ->
      let inp = { Eval.argv = args; stdin = ""; read_file = read_file_opt } in
      (match (try `Ok (Eval.run sp inp) with Eval.Spec_error m -> `Err m) with
       | `Err m -> Printf.eprintf "spec error: %s\n" m; exit 64
       | `Ok r ->
           print_string r.Eval.rstdout;
           (match r.Eval.rstderr with
            | Eval.SExact s -> output_string stderr s
            | Eval.SPred _ -> Printf.eprintf "%s: error\n" name (* stderr is free/uncertified *));
           exit r.Eval.rexit)

let () =
  match Array.to_list Sys.argv with
  | _ :: "list" :: _ -> List.iter (fun (n, _) -> print_endline n) Specs.by_name
  | _ :: "check" :: name :: rest -> do_check name rest
  | _ :: "run" :: name :: "--" :: args -> do_run name args
  | _ -> print_string usage; exit 2
