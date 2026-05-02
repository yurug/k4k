(** [Backend_claude] — subprocess invocation of [claude -p] per
    [kb/external/claude-code.md]. *)

type config = {
  binary             : string;     (* "claude" by default *)
  hard_per_invocation: int;        (* preset budget cap *)
  max_retries        : int;
}

type t = {
  cfg     : config;
  used    : int ref;
  version : string;
}

let name = "claude-code"

let default_config = {
  binary = "claude";
  hard_per_invocation = 1000;
  max_retries = 3;
}

let version t = t.version

(* Probe [claude --version] once at create time. Returns
   "0.0.0-unknown" if the binary cannot be found. *)
let probe_version cfg =
  let cmd = Printf.sprintf "%s --version 2>/dev/null"
              (Filename.quote cfg.binary) in
  match Unix.open_process_in cmd with
  | exception _ -> "0.0.0-unknown"
  | ic ->
      let line = (try input_line ic with End_of_file -> "") in
      let _ = Unix.close_process_in ic in
      String.trim line

let create cfg = {
  cfg;
  used = ref 0;
  version = probe_version cfg;
}

(* --- subprocess shell --- *)

let read_all ic =
  let buf = Buffer.create 4096 in
  try
    while true do
      Buffer.add_channel buf ic 4096
    done; assert false
  with End_of_file -> Buffer.contents buf

let permission_mode_for = function
  | `Formalization -> "readOnly"
  | `Gap_step      -> "acceptEdits"
  | `Kb_regen      -> "readOnly"

let max_turns_for = function
  | `Formalization -> 1
  | `Gap_step      -> 4
  | `Kb_regen      -> 1

let build_argv ~cfg ~purpose ~prompt =
  [| cfg.binary;
     "-p"; prompt;
     "--output-format"; "json";
     "--max-turns"; string_of_int (max_turns_for purpose);
     "--permission-mode"; permission_mode_for purpose;
     "--no-color"; |]

let run_one_call ~cfg ~purpose ~prompt =
  let argv = build_argv ~cfg ~purpose ~prompt in
  let pin, pout, perr =
    Unix.open_process_args_full
      cfg.binary argv (Unix.environment ()) in
  close_out pout;
  let stdout_text = read_all pin in
  let stderr_text = read_all perr in
  let status = Unix.close_process_full (pin, pout, perr) in
  (status, stdout_text, stderr_text)

(* --- response parsing --- *)

let parse_response raw =
  match Yojson.Safe.from_string raw with
  | exception Yojson.Json_error msg ->
      Error (Printf.sprintf "claude wrapper JSON: %s" msg)
  | `Assoc fs ->
      let text =
        match List.assoc_opt "result" fs with
        | Some (`Assoc rfs) ->
            (match List.assoc_opt "text" rfs with
             | Some (`String s) -> s
             | _ -> "")
        | _ -> ""
      in
      let used =
        match List.assoc_opt "usage" fs with
        | Some (`Assoc ufs) ->
            let g k = match List.assoc_opt k ufs with
              | Some (`Int i) -> i | _ -> 0 in
            g "input_tokens" + g "output_tokens"
        | _ -> 0
      in
      Ok (text, used)
  | _ -> Error "claude wrapper: not a JSON object"

let is_auth_error stderr =
  let lower = String.lowercase_ascii stderr in
  Astring.String.is_infix ~affix:"not authenticated" lower
  || Astring.String.is_infix ~affix:"unauthenticated" lower
  || Astring.String.is_infix ~affix:"401" lower

let is_transient stderr =
  let lower = String.lowercase_ascii stderr in
  Astring.String.is_infix ~affix:"rate limit" lower
  || Astring.String.is_infix ~affix:"timeout" lower
  || Astring.String.is_infix ~affix:"429" lower
  || Astring.String.is_infix ~affix:"503" lower

let backoff_seconds attempt =
  (* 0.5s, 1s, 2s — capped so retries cost bounded wall-clock. *)
  let base = 0.5 *. (Float.of_int (1 lsl attempt)) in
  Float.min base 4.0

let invoke t ~purpose ~prompt ~budget =
  let cfg = t.cfg in
  if !(t.used) + budget > cfg.hard_per_invocation then
    `Budget_exhausted
  else begin
    let rec attempt n =
      if n > cfg.max_retries then
        `Tool_error "claude: too many retries"
      else
        match run_one_call ~cfg ~purpose ~prompt with
        | exception (Unix.Unix_error (Unix.ENOENT, _, _)) ->
            `Tool_error (Printf.sprintf "claude binary not found: %s" cfg.binary)
        | exception e ->
            `Tool_error (Printexc.to_string e)
        | (Unix.WEXITED 0, stdout_text, _stderr) ->
            (match parse_response stdout_text with
             | Error msg -> `Tool_error msg
             | Ok (text, used) ->
                 t.used := !(t.used) + used;
                 `Ok Agent_backend.{ text; budget_used = used;
                                     duration_ms = 0 })
        | (_, _, stderr_text) when is_auth_error stderr_text ->
            `Tool_error "claude: not authenticated"
        | (_, _, stderr_text) when is_transient stderr_text
                                 && n < cfg.max_retries ->
            Unix.sleepf (backoff_seconds n);
            attempt (n + 1)
        | (Unix.WEXITED n, _, stderr_text) ->
            `Tool_error (Printf.sprintf "claude exit %d: %s"
                           n (String.trim stderr_text))
        | (Unix.WSIGNALED s, _, _) ->
            `Tool_error (Printf.sprintf "claude killed by signal %d" s)
        | (Unix.WSTOPPED s, _, _) ->
            `Tool_error (Printf.sprintf "claude stopped by signal %d" s)
    in
    attempt 0
  end
