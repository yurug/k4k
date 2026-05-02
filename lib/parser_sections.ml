(** Internal ownership-tag scanner used by [Parser]. Pure. *)

type owner = [ `User | `K4k ]

type section = {
  owner        : owner;
  id           : string;
  hash         : string option;
  content      : string;
  start_offset : int;
  end_offset   : int;
  begin_line   : int;
}

let raise_format ~line ~col reason =
  raise (Error.K4k_error (Error.E_format { line; col; reason }))

let begin_re =
  Re.compile (
    Re.seq [
      Re.str "<!-- k4k:owner=";
      Re.group (Re.alt [ Re.str "user"; Re.str "k4k" ]);
      Re.str " begin id=";
      Re.group (Re.rep1 (Re.compl [ Re.set " \t\n>" ]));
      Re.opt (Re.seq [
        Re.rep1 Re.space;
        Re.str "hash=";
        Re.group (Re.rep1 (Re.compl [ Re.set " \t\n>" ]));
      ]);
      Re.rep Re.space;
      Re.str "-->";
    ]
  )

let end_re =
  Re.compile (
    Re.seq [
      Re.str "<!-- k4k:owner=";
      Re.group (Re.alt [ Re.str "user"; Re.str "k4k" ]);
      Re.rep1 Re.space;
      Re.str "end -->";
    ]
  )

let line_of_offset s off =
  let n = ref 1 in
  for i = 0 to min (off - 1) (String.length s - 1) do
    if s.[i] = '\n' then incr n
  done;
  !n

let owner_of_str = function
  | "user" -> `User
  | "k4k"  -> `K4k
  | _      -> assert false

let unmatched_begin_msg id =
  Printf.sprintf "unmatched begin tag for id=%s" id

let owner_mismatch_msg id b e =
  Printf.sprintf "owner mismatch on end tag for id=%s (begin=%s, end=%s)" id b e

let missing_hash_msg id =
  Printf.sprintf "owner=k4k section %s missing hash= attribute" id

type begin_match = {
  beg_start : int;
  beg_end   : int;
  owner_str : string;
  id        : string;
  hash      : string option;
}

let parse_begin g = {
  beg_start = Re.Group.start g 0;
  beg_end   = Re.Group.stop  g 0;
  owner_str = Re.Group.get g 1;
  id        = Re.Group.get g 2;
  hash      = (try Some (Re.Group.get g 3) with Not_found -> None);
}

let find_end raw bm =
  match Re.exec_opt ~pos:bm.beg_end end_re raw with
  | Some eg -> eg
  | None ->
      raise_format ~line:(line_of_offset raw bm.beg_start) ~col:1
        (unmatched_begin_msg bm.id)

let validate_owners raw bm eg =
  let end_start = Re.Group.start eg 0 in
  let end_owner = Re.Group.get eg 1 in
  if end_owner <> bm.owner_str then
    raise_format ~line:(line_of_offset raw end_start) ~col:1
      (owner_mismatch_msg bm.id bm.owner_str end_owner);
  end_start

let build_section raw bm end_start = {
  owner = owner_of_str bm.owner_str;
  id    = bm.id;
  hash  = bm.hash;
  content      = String.sub raw bm.beg_end (end_start - bm.beg_end);
  start_offset = bm.beg_end;
  end_offset   = end_start;
  begin_line   = line_of_offset raw bm.beg_start;
}

(* Match one section starting at [pos]; return [None] if no further section. *)
let match_one raw pos seen =
  match Re.exec_opt ~pos begin_re raw with
  | None -> None
  | Some g ->
      let bm = parse_begin g in
      if List.mem bm.id seen then
        raise_format ~line:(line_of_offset raw bm.beg_start) ~col:1
          (Printf.sprintf "duplicate section id: %s" bm.id);
      if bm.owner_str = "k4k" && bm.hash = None then
        raise_format ~line:(line_of_offset raw bm.beg_start) ~col:1
          (missing_hash_msg bm.id);
      let eg = find_end raw bm in
      let end_start = validate_owners raw bm eg in
      let sec = build_section raw bm end_start in
      Some (sec, Re.Group.stop eg 0)

let scan raw start =
  let rec loop pos acc seen =
    match match_one raw pos seen with
    | None -> List.rev acc
    | Some (sec, next_pos) -> loop next_pos (sec :: acc) (sec.id :: seen)
  in
  loop start [] []
