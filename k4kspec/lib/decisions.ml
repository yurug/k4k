(* Decisions — the D-numbered decision list (agent-authored, review input; lives in the
   ledger as decisions.md). D-numbers are MONOTONIC and IMMORTAL: revise may only append new
   entries and flip a status to [superseded-by:Dk]; existing entries are otherwise verbatim.
   check_monotone enforces that mechanically — a weak model that rewrites history gets a
   rejection naming the exact entry and field. Entry format:

     D3. [active] one-line title
       decided: what was decided
       alternatives: what else was considered
       why: the reason
       spec: case #N / case #N <chan> / case #N law #M / header
*)

type status = Active | Superseded of int

type entry = {
  id : int;
  status : status;
  title : string;
  decided : string;
  alternatives : string;
  why : string;
  spec_ref : string;
}

let field_names = [ "decided"; "alternatives"; "why"; "spec" ]

let parse_header (line : string) : (int * status * string) option =
  match Scanf.sscanf_opt line "D%d. [%[a-zA-Z0-9:-]] %[^\n]" (fun i st t -> (i, st, t)) with
  | Some (i, "active", t) -> Some (i, Active, t)
  | Some (i, st, t) -> (
      match Scanf.sscanf_opt st "superseded-by:D%d%!" (fun k -> k) with
      | Some k -> Some (i, Superseded k, t)
      | None -> None)
  | None -> None

let parse (src : string) : (entry list, string) result =
  let lines = String.split_on_char '\n' src in
  let entries = ref [] in
  (* current entry under construction: header + mutable field map *)
  let cur = ref None in
  let err = ref None in
  let fail m = if !err = None then err := Some m in
  let flush () =
    match !cur with
    | None -> ()
    | Some ((id, status, title), fields) ->
        let get k =
          match List.assoc_opt k !fields with
          | Some v -> Some (String.trim v)
          | None -> fail (Printf.sprintf "D%d is missing the `%s:` field" id k); None
        in
        (match get "decided", get "alternatives", get "why", get "spec" with
         | Some decided, Some alternatives, Some why, Some spec_ref ->
             entries := { id; status; title; decided; alternatives; why; spec_ref } :: !entries
         | _ -> ());
        cur := None
  in
  List.iter
    (fun line ->
      let t = String.trim line in
      if t = "" || (t.[0] = '#' && !cur = None) then ()
      else
        match parse_header t with
        | Some hdr -> flush (); cur := Some (hdr, ref [])
        | None -> (
            match !cur with
            | None -> fail (Printf.sprintf "unexpected line outside any entry: %S" t)
            | Some (_, fields) -> (
                match String.index_opt t ':' with
                | Some i when List.mem (String.sub t 0 i) field_names ->
                    let k = String.sub t 0 i in
                    let v = String.sub t (i + 1) (String.length t - i - 1) in
                    if List.mem_assoc k !fields then
                      fail (Printf.sprintf "duplicate `%s:` field" k)
                    else fields := (k, v) :: !fields
                | _ -> (
                    (* continuation of the most recent field *)
                    match !fields with
                    | (k, v) :: rest -> fields := (k, v ^ "\n" ^ t) :: rest
                    | [] -> fail (Printf.sprintf "text before the first field of an entry: %S" t)))))
    lines;
  flush ();
  match !err with
  | Some m -> Error m
  | None ->
      let es = List.rev !entries in
      (* ids strictly increasing *)
      let rec mono last = function
        | [] -> Ok es
        | e :: rest ->
            if e.id <= last then Error (Printf.sprintf "D-numbers must be strictly increasing (D%d after D%d)" e.id last)
            else mono e.id rest
      in
      (* superseded-by targets must exist *)
      let ids = List.map (fun e -> e.id) es in
      (match List.find_opt (fun e -> match e.status with Superseded k -> not (List.mem k ids) | Active -> false) es with
       | Some e ->
           Error (Printf.sprintf "D%d is superseded-by a D-number that does not exist" e.id)
       | None -> mono 0 es)

let max_id (es : entry list) : int = List.fold_left (fun m e -> max m e.id) 0 es

(* the immutable core of an entry (everything but status) *)
let core e = (e.id, e.title, e.decided, e.alternatives, e.why, e.spec_ref)

let check_monotone ~(old : entry list) ~(fresh : entry list) : (unit, string) result =
  let rec go = function
    | [] -> Ok ()
    | (o : entry) :: rest -> (
        match List.find_opt (fun f -> f.id = o.id) fresh with
        | None -> Error (Printf.sprintf "D%d was DROPPED — existing decisions are immortal; copy them verbatim" o.id)
        | Some f ->
            if core f <> core o then
              let field =
                if f.title <> o.title then "title"
                else if f.decided <> o.decided then "decided"
                else if f.alternatives <> o.alternatives then "alternatives"
                else if f.why <> o.why then "why"
                else "spec"
              in
              Error (Printf.sprintf "D%d's `%s` field CHANGED — existing decisions are immortal; copy them verbatim (only the status may flip to superseded-by)" o.id field)
            else
              match o.status, f.status with
              | Active, _ -> go rest                              (* Active may stay or become Superseded *)
              | Superseded k, Superseded k' when k = k' -> go rest
              | Superseded _, _ -> Error (Printf.sprintf "D%d's superseded status changed — statuses only move active -> superseded-by" o.id))
  in
  match go old with
  | Error e -> Error e
  | Ok () ->
      (* new entries must extend, not interleave *)
      let old_max = max_id old in
      (match List.find_opt (fun f -> f.id > 0 && f.id <= old_max && not (List.exists (fun o -> o.id = f.id) old)) fresh with
       | Some f -> Error (Printf.sprintf "D%d is NEW but numbered below the existing maximum D%d — new decisions get fresh numbers" f.id old_max)
       | None -> Ok ())
