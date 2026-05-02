type t =
  | Stable
  | Unstable of Error.issue list

let is_stable = function Stable -> true | Unstable _ -> false

let find_section sections id =
  List.find_opt (fun (s : Parser.section) ->
    s.id = id && s.owner = `User) sections

let is_blank s =
  let len = String.length s in
  let rec loop i =
    if i >= len then true
    else match s.[i] with
      | ' ' | '\t' | '\n' | '\r' -> loop (i + 1)
      | _ -> false
  in
  loop 0

let check_structural (file : Parser.interaction_file) =
  let issues =
    List.fold_left (fun acc id ->
      match find_section file.sections id with
      | None ->
          Error.issue ~section:id "missing required user-owned section" :: acc
      | Some s when is_blank s.content ->
          Error.issue ~line:s.begin_line ~section:id
            "required section is empty" :: acc
      | Some _ -> acc
    ) [] Parser.required_user_section_ids
  in
  match issues with
  | [] -> Stable
  | _  -> Unstable (List.rev issues)

(* Step 1: the semantic pass is a stub that always passes. The real
   formalization-pass logic lands in step 2. *)
let check_semantic _file = Stable
