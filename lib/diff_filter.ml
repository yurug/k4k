(** [Diff_filter] — see [.mli]. *)

let target_paths (diff : string) : string list =
  let strip_b s =
    let n = String.length s in
    if n >= 2 && String.sub s 0 2 = "b/" then String.sub s 2 (n - 2) else s
  in
  let lines = String.split_on_char '\n' diff in
  List.fold_left (fun acc line ->
    let len = String.length line in
    if len >= 4 && String.sub line 0 4 = "+++ " then
      let rest = String.trim (String.sub line 4 (len - 4)) in
      let rest =
        match String.index_opt rest '\t' with
        | Some i -> String.sub rest 0 i | None -> rest
      in
      if rest = "/dev/null" || rest = "" then acc
      else strip_b rest :: acc
    else acc) [] lines

let starts_with prefix s =
  let lp = String.length prefix and ls = String.length s in
  ls >= lp && String.sub s 0 lp = prefix

(* Embedded [/..] segment (anywhere in the path, not just leading). *)
let has_dotdot_segment p =
  let n = String.length p in
  let rec scan i =
    if i + 3 > n then false
    else if String.sub p i 3 = "/.." && (i + 3 = n || p.[i + 3] = '/')
    then true
    else scan (i + 1)
  in
  scan 0

let is_forbidden (path : string) : bool =
  if path = "" then true
  else if path.[0] = '/' then true
  else if starts_with "../" path || path = ".." then true
  else if has_dotdot_segment path then true
  else if path = ".k4k" || starts_with ".k4k/" path then true
  else if path = ".git" || starts_with ".git/" path then true
  else false

let first_forbidden (diff : string) : string option =
  let rec scan = function
    | [] -> None
    | p :: rest -> if is_forbidden p then Some p else scan rest
  in
  scan (target_paths diff)
