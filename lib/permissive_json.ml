(** Permissive JSON pre-processing per [conventions/context-economy.md]
    rule R7. Strips ```json/``` code fences, leading/trailing prose, and
    light trailing-comma sloppiness so the strict downstream decoder
    sees clean JSON. *)

(* Find the start of the first { and the matching closing } at the same
   depth, then ignore anything before and after. Strings (with escaped
   characters) are tracked so braces inside them don't count. *)

let find_object_bounds s =
  let len = String.length s in
  let lo = ref (-1) in
  let depth = ref 0 in
  let in_str = ref false in
  let escape = ref false in
  let hi = ref (-1) in
  let i = ref 0 in
  while !i < len && !hi < 0 do
    let c = s.[!i] in
    if !in_str then begin
      if !escape then escape := false
      else if c = '\\' then escape := true
      else if c = '"' then in_str := false
    end else begin
      match c with
      | '"' -> in_str := true
      | '{' ->
          if !lo < 0 then lo := !i;
          incr depth
      | '}' ->
          decr depth;
          if !depth = 0 && !lo >= 0 then hi := !i
      | _ -> ()
    end;
    incr i
  done;
  if !lo >= 0 && !hi >= !lo then Some (!lo, !hi)
  else None

let strip_trailing_commas s =
  (* Replace [, }] with [ }] and [, ]] with [ ]]; conservative on strings. *)
  let len = String.length s in
  let buf = Buffer.create len in
  let in_str = ref false in
  let escape = ref false in
  let i = ref 0 in
  while !i < len do
    let c = s.[!i] in
    if !in_str then begin
      Buffer.add_char buf c;
      if !escape then escape := false
      else if c = '\\' then escape := true
      else if c = '"' then in_str := false
    end else if c = '"' then begin
      Buffer.add_char buf c;
      in_str := true
    end else if c = ',' then begin
      let j = ref (!i + 1) in
      while !j < len && (s.[!j] = ' ' || s.[!j] = '\t'
                         || s.[!j] = '\n' || s.[!j] = '\r')
      do incr j done;
      if !j < len && (s.[!j] = '}' || s.[!j] = ']') then ()
      else Buffer.add_char buf c
    end else
      Buffer.add_char buf c;
    incr i
  done;
  Buffer.contents buf

let extract s =
  match find_object_bounds s with
  | None -> raise (Error.K4k_error
                     (Error.E_format
                        { line = 0; col = 0;
                          reason = "no JSON object found in response" }))
  | Some (lo, hi) ->
      let raw = String.sub s lo (hi - lo + 1) in
      strip_trailing_commas raw

let parse s =
  let cleaned = extract s in
  try Yojson.Safe.from_string cleaned
  with Yojson.Json_error msg ->
    raise (Error.K4k_error
             (Error.E_format
                { line = 0; col = 0;
                  reason = Printf.sprintf "permissive JSON parse: %s" msg }))
