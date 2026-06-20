(* trusted I/O shim: real argv/stdout/stderr <-> the extracted pure `run` *)
let to_cl (s : string) : char list = List.init (String.length s) (String.get s)
let of_cl (l : char list) : string = String.of_seq (List.to_seq l)
let () =
  let args = match Array.to_list Sys.argv with _ :: r -> r | [] -> [] in
  let o = Upper_ext.run (List.map to_cl args) in
  print_string (of_cl o.Upper_ext.stdout);
  prerr_string (of_cl o.Upper_ext.stderr);
  exit o.Upper_ext.exit
