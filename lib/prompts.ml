(** [Prompts] — minimal {{var}} substitution + prompt loading per Q3.1.

    Templates live in [prompts/] at repo root. Substitution is pure
    string replacement. *)

let substitute (template : string) (vars : (string * string) list) : string =
  List.fold_left (fun acc (k, v) ->
    let needle = "{{" ^ k ^ "}}" in
    Astring.String.cuts ~sep:needle acc |> String.concat v
  ) template vars

(* The path-search strategy mirrors integration tests: walk up from cwd
   to find the dune-project root, then look at [prompts/<name>.md]. *)

let rec find_root dir =
  if Sys.file_exists (Filename.concat dir "dune-project") then Some dir
  else
    let p = Filename.dirname dir in
    if p = dir then None else find_root p

let template_path name =
  match find_root (Sys.getcwd ()) with
  | None -> None
  | Some root ->
      let p = Filename.concat root (Filename.concat "prompts" name) in
      if Sys.file_exists p then Some p else None

let embedded = function
  | "formalize.md"        -> Some Embedded_prompts.formalize
  | "gap-step.tier-a.md"  -> Some Embedded_prompts.gap_step_tier_a
  | "gap-step.tier-b.md"  -> Some Embedded_prompts.gap_step_tier_b
  | "gap-step.tier-c.md"  -> Some Embedded_prompts.gap_step_tier_c
  | "kb-regen.md"         -> Some Embedded_prompts.kb_regen
  | _                     -> None

let load name =
  match template_path name with
  | Some p -> Persist.read_file p
  | None ->
      (match embedded name with
       | Some s -> s
       | None ->
           raise (Error.K4k_error (Error.E_state_corrupt
             (Printf.sprintf "prompt template not found: %s" name))))

let strip_frontmatter s =
  let lines = String.split_on_char '\n' s in
  match lines with
  | "---" :: rest ->
      let rec drop = function
        | [] -> []
        | "---" :: tl -> tl
        | _ :: tl -> drop tl
      in
      String.concat "\n" (drop rest)
  | _ -> s

let render name vars =
  let raw = load name in
  let body = strip_frontmatter raw in
  substitute body vars
