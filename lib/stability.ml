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

(* Step 2: legacy semantic stub kept for backward compatibility with
   step 1 tests (it always reports stable). The real two-run protocol
   lives in [check_semantic_with_backend] below. *)
let check_semantic _file = Stable

(* --- step 2: two-run formalization protocol --- *)

let user_section_hashes (file : Parser.interaction_file) =
  List.filter_map (fun (s : Parser.section) ->
    match s.owner with
    | `User -> Some (s.id, Persist.sha256_hex s.content)
    | `K4k -> None
  ) file.sections

let cache_hit ~prev_hashes ~current_hashes =
  let same kvs1 kvs2 =
    List.length kvs1 = List.length kvs2 &&
    List.for_all (fun (k, v) ->
      match List.assoc_opt k kvs2 with
      | Some v' -> String.equal v v'
      | None -> false) kvs1
  in
  same prev_hashes current_hashes

type semantic_outcome =
  | Sem_cached  of Characterization.t
  | Sem_stable  of Characterization.t * string list  (* run-ids written *)
  | Sem_unstable of Error.issue list * string list   (* issues + run-ids *)

let render_user_sections (file : Parser.interaction_file) =
  let buf = Buffer.create 1024 in
  List.iter (fun (s : Parser.section) ->
    match s.owner with
    | `User ->
        Buffer.add_string buf "## ";
        Buffer.add_string buf s.id;
        Buffer.add_char buf '\n';
        Buffer.add_string buf s.content;
        Buffer.add_char buf '\n'
    | `K4k -> ()
  ) file.sections;
  Buffer.contents buf

let one_run ~k4k_dir ~run_id ~prompt ~response_text =
  Persist.write_agent_run ~k4k_dir ~run_id ~prompt
    ~response:response_text
    ~verdict:{|{"outcome":"applied"}|};
  match Permissive_json.parse response_text with
  | exception Error.K4k_error (Error.E_format { reason; _ }) ->
      Error reason
  | v ->
      (match Characterization_decoder.of_yojson v with
       | exception Error.K4k_error (Error.E_format { reason; _ }) ->
           Error reason
       | parsed -> Ok (Canonicalize.canonicalize parsed))

type 'b backend_invoker = {
  invoke :
    purpose:Agent_backend.purpose ->
    prompt:string ->
    budget:int ->
    Agent_backend.result;
  bk : 'b;
}

let invoke_or_raise inv ~prompt ~budget =
  match inv.invoke ~purpose:`Formalization ~prompt ~budget with
  | `Ok r -> r.text
  | `Budget_exhausted ->
      raise (Error.K4k_error
        (Error.E_budget { used = budget; cap = budget }))
  | `Tool_error msg ->
      raise (Error.K4k_error (Error.E_agent_unavailable msg))

let rec semantic_check_with_backend
    ~k4k_dir ~prompt ~budget
    ~(prev_hashes : (string * string) list)
    ~(current_hashes : (string * string) list)
    ~(cached_desired : Characterization.t option)
    inv =
  if cache_hit ~prev_hashes ~current_hashes then
    match cached_desired with
    | Some d -> Sem_cached d
    | None ->
        (* Hashes match but no D — fall through to formalization. *)
        run_two ~k4k_dir ~prompt ~budget inv
  else
    run_two ~k4k_dir ~prompt ~budget inv

and write_divergence ~k4k_dir id_a id_b ca cb =
  let av = Characterization_json.to_yojson ca in
  let bv = Characterization_json.to_yojson cb in
  let report = {
    Divergence.run_a_id = id_a;
    run_b_id = id_b;
    hash_a = ca.Characterization.hash;
    hash_b = cb.Characterization.hash;
    diff_paths = Divergence.diff av bv;
  } in
  let bytes = Yojson.Safe.pretty_to_string ~std:true
    (Divergence.to_yojson report) in
  Persist.write_divergence_report ~k4k_dir ~run_id:id_a ~report:bytes

and combine ~k4k_dir id_a id_b r_a r_b =
  match r_a, r_b with
  | Ok ca, Ok cb when Canonicalize.equal ca cb ->
      Sem_stable (ca, [id_a; id_b])
  | Ok ca, Ok cb ->
      write_divergence ~k4k_dir id_a id_b ca cb;
      let msg = Printf.sprintf
        "two formalization runs produced different ASTs (%s vs %s); see %s/divergence.json"
        (String.sub ca.hash 0 7) (String.sub cb.hash 0 7) id_a in
      Sem_unstable ([Error.issue ~section:"formalization" msg],
                    [id_a; id_b])
  | Error msg_a, Error msg_b ->
      Sem_unstable
        ([Error.issue ~section:"formalization"
            (Printf.sprintf "both runs invalid: a=%s; b=%s" msg_a msg_b)],
         [id_a; id_b])
  | Error msg, Ok _ ->
      Sem_unstable
        ([Error.issue ~section:"formalization"
            (Printf.sprintf "first run invalid: %s" msg)],
         [id_a; id_b])
  | Ok _, Error msg ->
      Sem_unstable
        ([Error.issue ~section:"formalization"
            (Printf.sprintf "second run invalid: %s" msg)],
         [id_a; id_b])

and run_two ~k4k_dir ~prompt ~budget inv =
  let id_a = Persist.agent_run_id () in
  let text_a = invoke_or_raise inv ~prompt ~budget in
  let r_a = one_run ~k4k_dir ~run_id:id_a ~prompt ~response_text:text_a in
  let id_b = Persist.agent_run_id () in
  let text_b = invoke_or_raise inv ~prompt ~budget in
  let r_b = one_run ~k4k_dir ~run_id:id_b ~prompt ~response_text:text_b in
  combine ~k4k_dir id_a id_b r_a r_b
