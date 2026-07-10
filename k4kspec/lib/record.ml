(* Record — the one on-disk format for k4k machine records (.sig files, proposal files).
   Shape:
     # comment                     (column-0 '#', header area only)
     key: value
     key: value that continues
      on a folded line            (a leading space/tab continues the previous value with '\n')
     == section-name ==
     <verbatim body until the next section header or EOF>
   Repeated keys accumulate in order. Section bodies are normalized to end with exactly one
   newline. A body line matching `== ... ==` at column 0 would start a new section —
   k4kspec/hints/markdown content never produces such a line. *)

type t = { fields : (string * string) list; sections : (string * string) list }

let is_section_header line =
  String.length line >= 5
  && String.sub line 0 3 = "== "
  && String.sub line (String.length line - 3) 3 = " =="

let section_name line = String.trim (String.sub line 3 (String.length line - 6))

let to_string (r : t) : string =
  let b = Buffer.create 256 in
  List.iter
    (fun (k, v) ->
      (* fold embedded newlines: continuation lines carry one leading space *)
      let folded = String.concat "\n " (String.split_on_char '\n' v) in
      Buffer.add_string b (k ^ ": " ^ folded ^ "\n"))
    r.fields;
  List.iter
    (fun (name, body) ->
      Buffer.add_string b ("== " ^ name ^ " ==\n");
      Buffer.add_string b body;
      if body = "" || body.[String.length body - 1] <> '\n' then Buffer.add_char b '\n')
    r.sections;
  Buffer.contents b

let of_string (s : string) : t =
  (* split on newlines; the file's final newline yields a trailing "" element — drop it *)
  let lines =
    match List.rev (String.split_on_char '\n' s) with
    | "" :: rest -> List.rev rest
    | l -> List.rev l
  in
  let fields = ref [] and sections = ref [] in
  let cur = ref None in                                   (* Some (name, rev body lines) *)
  let flush () =
    match !cur with
    | Some (name, rev_body) ->
        sections := (name, String.concat "\n" (List.rev rev_body) ^ "\n") :: !sections;
        cur := None
    | None -> ()
  in
  List.iter
    (fun line ->
      if is_section_header line then (flush (); cur := Some (section_name line, []))
      else
        match !cur with
        | Some (name, b) -> cur := Some (name, line :: b)
        | None ->
            if line = "" || line.[0] = '#' then ()
            else if line.[0] = ' ' || line.[0] = '\t' then (
              match !fields with
              | (k, v) :: rest ->
                  fields := (k, v ^ "\n" ^ String.sub line 1 (String.length line - 1)) :: rest
              | [] -> failwith "record: continuation line before any field")
            else
              match String.index_opt line ':' with
              | Some i ->
                  let k = String.sub line 0 i in
                  let v = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
                  fields := (k, v) :: !fields
              | None -> failwith (Printf.sprintf "record: malformed line %S" line))
    lines;
  flush ();
  { fields = List.rev !fields; sections = List.rev !sections }

let get (r : t) (k : string) : string option = List.assoc_opt k r.fields
let get_all (r : t) (k : string) : string list =
  List.filter_map (fun (k', v) -> if k' = k then Some v else None) r.fields
let section (r : t) (name : string) : string option = List.assoc_opt name r.sections
