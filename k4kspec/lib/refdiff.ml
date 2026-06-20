(* OPTIONAL clone plug (a SPECIAL CASE, not the spine of validation).
   When a reference binary exists, differentially test the spec's determined
   channels (stdout, exit) against it. Only meaningful when the spec's argv maps
   positionally onto the tool's CLI (e.g. grepf vs `grep -F NEEDLE FILE`); it does
   NOT map for tools whose CLI differs (e.g. cutf vs `cut -d, -f2`), which is itself
   a useful thing to discover. *)

let which (prog : string) : string option =
  if String.contains prog '/' then (if Sys.file_exists prog then Some prog else None)
  else
    let dirs = String.split_on_char ':' (try Sys.getenv "PATH" with Not_found -> "/usr/bin:/bin") in
    List.find_map (fun d -> let p = Filename.concat d prog in if Sys.file_exists p then Some p else None) dirs

let read_file_rm f = let ic = open_in_bin f in let n = in_channel_length ic in
  let s = really_input_string ic n in close_in ic; (try Sys.remove f with _ -> ()); s

(* run argv (full path in head) in [cwd]; return (exit, stdout, stderr) *)
let run_cmd (argv : string list) ~cwd : int * string * string =
  let out = Filename.temp_file "k4k_o" "" and err = Filename.temp_file "k4k_e" "" in
  let fo = Unix.openfile out [ O_WRONLY; O_TRUNC ] 0o600 in
  let fe = Unix.openfile err [ O_WRONLY; O_TRUNC ] 0o600 in
  let dnull = Unix.openfile "/dev/null" [ O_RDONLY ] 0 in
  let cwd0 = Unix.getcwd () in
  Unix.chdir cwd;
  let pid = Unix.create_process (List.hd argv) (Array.of_list argv) dnull fo fe in
  Unix.chdir cwd0;
  List.iter Unix.close [ fo; fe; dnull ];
  let _, status = Unix.waitpid [] pid in
  let code = match status with Unix.WEXITED c -> c | WSIGNALED s | WSTOPPED s -> 128 + s in
  (code, read_file_rm out, read_file_rm err)

type div = { argv : string list; field : string; want : string; got : string }

(* refcmd e.g. "grep -F" ; we append the spec's argv positionally. *)
let diff (sp : Ast.spec) (refcmd : string) : (div list, string) result =
  match String.split_on_char ' ' (String.trim refcmd) |> List.filter (fun s -> s <> "") with
  | [] -> Error "empty reference command"
  | prog :: base -> (
      match which prog with
      | None -> Error (Printf.sprintf "reference %s not found on PATH" prog)
      | Some progpath ->
          let divs = ref [] in
          List.iter
            (fun (argv, files) ->
              let dir = Filename.temp_file "k4kdir" "" in
              Sys.remove dir; Unix.mkdir dir 0o700;
              List.iter (fun (p, c) -> let oc = open_out_bin (Filename.concat dir p) in output_string oc c; close_out oc) files;
              let oracle = try Some (Eval.run sp (Eval.input_of argv files)) with Eval.Spec_error _ -> None in
              (match oracle with
               | None -> ()
               | Some r ->
                   let rexit, rout, _ = run_cmd (progpath :: base @ ("--" :: argv)) ~cwd:dir in
                   if rout <> r.Eval.rstdout then divs := { argv; field = "stdout"; want = Check.esc r.Eval.rstdout; got = Check.esc rout } :: !divs;
                   if rexit <> r.Eval.rexit then divs := { argv; field = "exit"; want = string_of_int r.Eval.rexit; got = string_of_int rexit } :: !divs);
              (* cleanup *)
              List.iter (fun (p, _) -> try Sys.remove (Filename.concat dir p) with _ -> ()) files;
              (try Unix.rmdir dir with _ -> ()))
            (Check.scenarios sp);
          Ok (List.rev !divs))
