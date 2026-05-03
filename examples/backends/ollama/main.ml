(** Reference agent backend — Ollama (local LLM via HTTP).

    Standalone binary that conforms to k4k's agent-backend wire
    protocol (see [kb/external/backend-protocol.md]). It is NOT linked
    into k4k.

    Invocation (k4k passes the four protocol flags; the user prefixes
    any extras via [k4k.backend.command]):

      ollama_backend [--model NAME] [--host URL] [--mock-response PATH] \
        --purpose <formalization|gap-step|kb-regen> \
        --prompt-file <abs-path> --budget <int> --output <abs-path>

    Behavior:
      - Reads the prompt file.
      - POSTs to <host>/api/generate with body
        {"model": "<name>", "prompt": "<text>", "stream": false}.
      - Parses Ollama's JSON for [response], [prompt_eval_count],
        [eval_count]. Sums the eval counts as [budget_used].
      - If [budget_used > --budget] → outcome=budget_exhausted.
      - If [curl] exits non-zero (connection refused, timeout, …) →
        outcome=tool_error, with a human-readable error.
      - Emits the protocol result JSON atomically.
      - Exits 0 on a written result file (incl. tool_error outcome).
      - Exits 1 only when the [curl] binary itself is missing.

    Test mode: --mock-response <path> bypasses curl and reads a canned
    Ollama-shaped JSON response from <path>. Same pattern as
    K4K_STUB_RESPONSES on the k4k side. *)

open K4k

(* ---------- argv parsing ---------- *)

type purpose = [ `Formalization | `Gap_step | `Kb_regen ]

type args = {
  purpose       : purpose;
  prompt_file   : string;
  budget        : int;
  output        : string;
  model         : string;
  host          : string;
  mock_response : string option;
}

let purpose_of_string = function
  | "formalization" -> Some `Formalization
  | "gap-step"      -> Some `Gap_step
  | "kb-regen"      -> Some `Kb_regen
  | _               -> None

let parse_args argv =
  let n = Array.length argv in
  let purpose = ref None in
  let prompt_file = ref "" in
  let budget = ref 0 in
  let output = ref "" in
  let model = ref "codellama:7b-instruct" in
  let host = ref "http://localhost:11434" in
  let mock = ref None in
  let i = ref 1 in
  while !i < n do
    (match argv.(!i) with
     | "--purpose"       when !i + 1 < n ->
         purpose := purpose_of_string argv.(!i + 1); i := !i + 2
     | "--prompt-file"   when !i + 1 < n ->
         prompt_file := argv.(!i + 1); i := !i + 2
     | "--budget"        when !i + 1 < n ->
         budget := (try int_of_string argv.(!i + 1) with _ -> 0);
         i := !i + 2
     | "--output"        when !i + 1 < n ->
         output := argv.(!i + 1); i := !i + 2
     | "--model"         when !i + 1 < n ->
         model := argv.(!i + 1); i := !i + 2
     | "--host"          when !i + 1 < n ->
         host := argv.(!i + 1); i := !i + 2
     | "--mock-response" when !i + 1 < n ->
         mock := Some argv.(!i + 1); i := !i + 2
     | _ -> incr i)
  done;
  match !purpose with
  | None -> None
  | Some p ->
      if !prompt_file = "" || !output = "" || !budget <= 0 then None
      else Some { purpose = p; prompt_file = !prompt_file;
                  budget = !budget; output = !output;
                  model = !model; host = !host;
                  mock_response = !mock }

(* ---------- request / response ---------- *)

(* [options.num_predict = budget] preempts runaway generation. The
   cap counts output tokens only (Ollama doesn't enforce a total-token
   ceiling). The post-hoc [budget_used > budget] check in
   [interpret_ollama] is the backstop when the prompt itself blows the
   budget — both layers are needed to honor the protocol's "MUST
   refuse with budget_exhausted rather than exceed it" clause. *)
let body_of ~model ~prompt ~budget : string =
  let j : Yojson.Safe.t = `Assoc [
    "model",  `String model;
    "prompt", `String prompt;
    "stream", `Bool false;
    "options", `Assoc [ "num_predict", `Int budget ];
  ] in
  Canonical_json.to_string j

(** [parse_ollama_json raw] — extract [response] text + token usage
    from a non-streamed [/api/generate] response.

    Returns [Error msg] when:
    - the body is not valid JSON / not an object
    - the body has an [error] field (e.g. unknown model)
    - the body is well-formed but has no [response] field at all
      (e.g. some early-error shapes Ollama returns)

    Returns [Ok (text, used)] only when [response] is present (possibly
    empty string after a successful but trivial completion). Missing
    [prompt_eval_count] / [eval_count] are tolerated (treated as 0). *)
let parse_ollama_json raw =
  match Yojson.Safe.from_string raw with
  | exception Yojson.Json_error msg ->
      Error (Printf.sprintf "ollama JSON: %s" msg)
  | exception _ -> Error "ollama JSON: malformed"
  | `Assoc fs ->
      (match List.assoc_opt "error" fs with
       | Some (`String e) -> Error ("ollama error: " ^ e)
       | Some _ -> Error "ollama: error field present (non-string)"
       | None ->
           match List.assoc_opt "response" fs with
           | None -> Error "ollama: no 'response' field"
           | Some (`String text) ->
               let g_int k = match List.assoc_opt k fs with
                 | Some (`Int i) -> i | _ -> 0 in
               let used =
                 g_int "prompt_eval_count" + g_int "eval_count" in
               Ok (text, used)
           | Some _ -> Error "ollama: 'response' field is not a string")
  | _ -> Error "ollama: not a JSON object"

(* ---------- curl subprocess ---------- *)

let body_path_of ~prompt_file =
  prompt_file ^ ".ollama-body.json"

let curl_args ~host ~body_path ~timeout_s =
  ["-sS";
   "-X"; "POST";
   "-H"; "Content-Type: application/json";
   "--max-time"; string_of_int timeout_s;
   "--data-binary"; "@" ^ body_path;
   host ^ "/api/generate"]

(* ---------- result file emission ---------- *)

let result_json_ok ~text ~budget_used ~duration_ms : Yojson.Safe.t =
  `Assoc [
    "outcome", `String "ok";
    "text", `String text;
    "budget_used", `Int budget_used;
    "duration_ms", `Int duration_ms;
  ]

let result_json_budget_exhausted ~duration_ms : Yojson.Safe.t =
  `Assoc [
    "outcome", `String "budget_exhausted";
    "duration_ms", `Int duration_ms;
  ]

let result_json_tool_error ~duration_ms ~error : Yojson.Safe.t =
  `Assoc [
    "outcome", `String "tool_error";
    "error", `String error;
    "duration_ms", `Int duration_ms;
  ]

let write_result ~output (j : Yojson.Safe.t) =
  Persist.atomic_write ~path:output (Canonical_json.to_string j)

(* ---------- main flow ---------- *)

let read_prompt path =
  try Ok (Persist.read_file path)
  with _ -> Error ("could not read prompt file: " ^ path)

(** Convert raw Ollama stdout into the protocol's outcome record. *)
let interpret_ollama ~budget ~duration_ms raw =
  match parse_ollama_json raw with
  | Error msg -> result_json_tool_error ~duration_ms ~error:msg
  | Ok (_, used) when used > budget ->
      result_json_budget_exhausted ~duration_ms
  | Ok (text, used) ->
      result_json_ok ~text ~budget_used:used ~duration_ms

let run_curl ~host ~body_path ~timeout_s =
  match Subprocess.run ~prog:"curl"
          ~args:(curl_args ~host ~body_path ~timeout_s)
          ~timeout_s () with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> `Missing
  | sub -> `Result sub

let interpret_curl ~budget ~duration_ms (sub : Subprocess.result) =
  if sub.timed_out then
    result_json_tool_error ~duration_ms ~error:"ollama: curl timed out"
  else if sub.exit_code = 130 then
    result_json_tool_error ~duration_ms ~error:"ollama: interrupted"
  else if sub.exit_code <> 0 then
    result_json_tool_error ~duration_ms
      ~error:(Printf.sprintf "ollama: curl exit %d: %s"
                sub.exit_code (String.trim sub.stderr))
  else
    interpret_ollama ~budget ~duration_ms sub.stdout

let with_request_body args ~prompt f =
  let body = body_of ~model:args.model ~prompt ~budget:args.budget in
  let path = body_path_of ~prompt_file:args.prompt_file in
  Persist.atomic_write ~path body;
  let r = f path in
  (try Sys.remove path with _ -> ());
  r

let run_live args ~prompt =
  let t0 = Unix.gettimeofday () in
  with_request_body args ~prompt (fun body_path ->
    match run_curl ~host:args.host ~body_path ~timeout_s:300 with
    | `Missing -> `Missing
    | `Result sub ->
        let elapsed = int_of_float
          ((Unix.gettimeofday () -. t0) *. 1000.0) in
        `Result (interpret_curl
                   ~budget:args.budget ~duration_ms:elapsed sub))

let run_mock args ~mock =
  let raw = Persist.read_file mock in
  `Result (interpret_ollama ~budget:args.budget ~duration_ms:0 raw)

let main args =
  match read_prompt args.prompt_file with
  | Error msg ->
      let j = result_json_tool_error ~duration_ms:0 ~error:msg in
      write_result ~output:args.output j; 0
  | Ok prompt ->
      let outcome = match args.mock_response with
        | Some mock -> run_mock args ~mock
        | None -> run_live args ~prompt
      in
      match outcome with
      | `Missing ->
          Printf.eprintf "ollama: curl binary not found on PATH\n"; 1
      | `Result j ->
          write_result ~output:args.output j; 0

let () =
  match parse_args Sys.argv with
  | None ->
      Printf.eprintf
        "usage: ollama_backend [--model NAME] [--host URL] \
         [--mock-response PATH] --purpose <formalization|gap-step|kb-regen> \
         --prompt-file <path> --budget <int> --output <path>\n";
      exit 1
  | Some args -> exit (main args)
