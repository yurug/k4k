(** [Diff_extract] — pure: pull the unified-diff payload out of an
    agent response per [prompts/gap-step.tier-{a,b,c}.md]'s output shape.

    The expected format is:
      ```json
      {"files": [...]}
      ```
      ```diff
      --- a/...
      +++ b/...
      @@ ... @@
      ```

    Tolerant: accepts the diff with or without ```diff fence; ignores
    surrounding prose. *)

let strip_lang_fence ~lang s =
  let pat = "```" ^ lang in
  match Astring.String.find_sub ~sub:pat s with
  | None -> None
  | Some start ->
      let after_open = start + String.length pat in
      (match Astring.String.find_sub
               ~start:after_open ~sub:"```" s with
       | None -> None
       | Some closing ->
           let content_start =
             match String.index_from_opt s after_open '\n' with
             | Some n -> n + 1
             | None -> after_open
           in
           if content_start >= closing then None
           else Some (String.sub s content_start (closing - content_start)))

let find_first_diff_block s =
  match strip_lang_fence ~lang:"diff" s with
  | Some d -> Some d
  | None ->
      (* Fallback: any fenced block whose first non-blank line starts
         with "--- ". *)
      (match strip_lang_fence ~lang:"" s with
       | Some d when Astring.String.is_prefix
                       ~affix:"--- " (String.trim d) -> Some d
       | _ ->
           (* Last resort: scan for "--- " line. *)
           let lines = String.split_on_char '\n' s in
           let starts_diff l =
             Astring.String.is_prefix ~affix:"--- " l in
           let rec drop_until = function
             | [] -> None
             | l :: rest when starts_diff l -> Some (l :: rest)
             | _ :: rest -> drop_until rest
           in
           (match drop_until lines with
            | None -> None
            | Some ls -> Some (String.concat "\n" ls)))

let extract_files s =
  match strip_lang_fence ~lang:"json" s with
  | None -> []
  | Some j ->
      (try
        match Yojson.Safe.from_string (String.trim j) with
        | `Assoc fs ->
            (match List.assoc_opt "files" fs with
             | Some (`List xs) ->
                 List.filter_map (function
                   | `String s -> Some s | _ -> None) xs
             | _ -> [])
        | _ -> []
      with Yojson.Json_error _ -> [])

let extract_diff (s : string) : string option =
  find_first_diff_block s
