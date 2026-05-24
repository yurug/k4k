(** Reference agent backend — Claude Code (claude -p).

    Standalone binary that conforms to k4k's agent-backend wire
    protocol (see kb/external/backend-protocol.md). It is NOT linked
    into k4k.

    Invocation:
      claude_code_backend --purpose <formalization|gap-step|kb-regen> \
        --prompt-file <abs-path> --budget <int> --output <abs-path>

    Behavior:
      - Reads the prompt file.
      - Passes --permission-mode acceptEdits. The k4k wire protocol's
        prompts never ask claude to invoke Edit/Write tools (formalize
        returns JSON text, gap-step returns a <patch> text block), so
        permission mode is just a safety policy and the value that
        works under --max-turns 1 + -p is the right one. The earlier
        "readOnly" choice was removed from the claude CLI's allowed
        set; "plan" is the closest semantic match but it makes claude
        call exit_plan_mode which adds noise under single-turn use.
      - Invokes [claude -p <prompt> --output-format json --max-turns 1].
      - Parses the JSON wrapper for result.text, usage.{input,output}_tokens.
      - Refuses with budget_exhausted if input+output > --budget.
      - Emits the protocol result JSON atomically.
      - Exits 0 on a written result file (incl. tool_error outcome).
      - Exits 1 only when the [claude] binary itself is missing. *)

open K4k

(* ---------- argv parsing ---------- *)

type purpose = [ `Formalization | `Gap_step | `Kb_regen ]

type args = {
  purpose       : purpose;
  prompt_file   : string;
  budget        : int;
  output        : string;
  mock_response : string option;
    (* Test mode: when set, the backend reads the JSON wrapper
       from this path instead of spawning [claude]. Parallel to
       ollama's [--mock-response]. Production users never set it. *)
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
  let mock_response = ref None in
  let i = ref 1 in
  while !i < n do
    let a = argv.(!i) in
    (match a with
     | "--purpose" when !i + 1 < n ->
         purpose := purpose_of_string argv.(!i + 1); i := !i + 2
     | "--prompt-file" when !i + 1 < n ->
         prompt_file := argv.(!i + 1); i := !i + 2
     | "--budget" when !i + 1 < n ->
         budget := (try int_of_string argv.(!i + 1) with _ -> 0);
         i := !i + 2
     | "--output" when !i + 1 < n ->
         output := argv.(!i + 1); i := !i + 2
     | "--mock-response" when !i + 1 < n ->
         mock_response := Some argv.(!i + 1); i := !i + 2
     | _ -> incr i)
  done;
  match !purpose with
  | None -> None
  | Some p ->
      if !prompt_file = "" || !output = "" || !budget <= 0 then None
      else Some { purpose = p; prompt_file = !prompt_file;
                  budget = !budget; output = !output;
                  mock_response = !mock_response }

(* ---------- claude invocation ---------- *)

(* Allowed values in the current claude CLI: acceptEdits, auto,
   bypassPermissions, default, dontAsk, plan. See the file-header
   comment for why we settle on acceptEdits for every purpose. *)
let permission_mode_for (_ : purpose) = "acceptEdits"

(* No --no-color: the claude CLI dropped that flag (2.1.x onwards) —
   --print mode is already plain text by default. We don't probe for
   it at runtime since the flag's absence is the documented behavior
   now, not an environment quirk. *)
let claude_args ~prompt ~purpose =
  ["-p"; prompt;
   "--output-format"; "json";
   "--max-turns"; "1";
   "--permission-mode"; permission_mode_for purpose]

(* ---------- result parsing ---------- *)

let parse_claude_json raw =
  match Yojson.Safe.from_string raw with
  | exception Yojson.Json_error msg ->
      Error (Printf.sprintf "claude wrapper JSON: %s" msg)
  | exception _ -> Error "claude wrapper JSON: malformed"
  | `Assoc fs ->
      let text =
        match List.assoc_opt "result" fs with
        | Some (`Assoc rfs) ->
            (match List.assoc_opt "text" rfs with
             | Some (`String s) -> s | _ -> "")
        | _ -> "" in
      let used =
        match List.assoc_opt "usage" fs with
        | Some (`Assoc ufs) ->
            let g k = match List.assoc_opt k ufs with
              | Some (`Int i) -> i | _ -> 0 in
            g "input_tokens" + g "output_tokens"
        | _ -> 0 in
      Ok (text, used)
  | _ -> Error "claude wrapper: not a JSON object"

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

let interpret_claude ~budget ~duration_ms (sub : Subprocess.result) =
  if sub.timed_out then
    result_json_tool_error ~duration_ms ~error:"claude timed out"
  else if sub.exit_code = 130 then
    result_json_tool_error ~duration_ms ~error:"claude interrupted"
  else if sub.exit_code <> 0 then
    result_json_tool_error ~duration_ms
      ~error:(Printf.sprintf "claude exit %d: %s" sub.exit_code
                (String.trim sub.stderr))
  else
    match parse_claude_json sub.stdout with
    | Error msg -> result_json_tool_error ~duration_ms ~error:msg
    | Ok (text, used) when used > budget ->
        result_json_budget_exhausted ~duration_ms
    | Ok (text, used) ->
        result_json_ok ~text ~budget_used:used ~duration_ms

let mock_subprocess raw : Subprocess.result =
  { exit_code = 0; stdout = raw; stderr = "";
    timed_out = false; duration_ms = 0 }

let run_backend args ~prompt =
  let t0 = Unix.gettimeofday () in
  let elapsed_ms () =
    int_of_float ((Unix.gettimeofday () -. t0) *. 1000.0) in
  match args.mock_response with
  | Some path ->
      (try
         let raw = Persist.read_file path in
         `Result (interpret_claude ~budget:args.budget
                    ~duration_ms:(elapsed_ms ())
                    (mock_subprocess raw))
       with _ ->
         `Result (result_json_tool_error ~duration_ms:(elapsed_ms ())
                    ~error:("could not read mock-response: " ^ path)))
  | None ->
      (match Subprocess.run ~prog:"claude"
               ~args:(claude_args ~prompt ~purpose:args.purpose)
               ~timeout_s:300 () with
       | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
           `Missing
       | sub ->
           `Result (interpret_claude
                      ~budget:args.budget
                      ~duration_ms:(elapsed_ms ()) sub))

let main args =
  match read_prompt args.prompt_file with
  | Error msg ->
      let j = result_json_tool_error ~duration_ms:0 ~error:msg in
      write_result ~output:args.output j; 0
  | Ok prompt ->
      match run_backend args ~prompt with
      | `Missing ->
          Printf.eprintf "claude binary not found on PATH\n"; 1
      | `Result j ->
          write_result ~output:args.output j; 0

let () =
  match parse_args Sys.argv with
  | None ->
      Printf.eprintf
        "usage: claude_code_backend --purpose <formalization|gap-step|kb-regen> \
         --prompt-file <path> --budget <int> --output <path>\n";
      exit 1
  | Some args -> exit (main args)
