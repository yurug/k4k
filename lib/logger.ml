type verbosity = [ `Quiet | `Verbose | `Debug ]

type t = {
  verbosity : verbosity;
  jsonl_path : string option;
}

let create ~verbosity ~jsonl_path = { verbosity; jsonl_path }

(* Match common secret-shaped strings (NF5).
   Two complementary patterns:
   - keyword <separator: : | => value: redacts everything from the
     keyword to the next whitespace / quote / comma / brace boundary.
   - "Bearer <token>" / "Token <token>" — redacts the value following
     a bareword Bearer/Token (HTTP Authorization style). *)
let secret_kw =
  Re.alt [
    Re.no_case (Re.str "api_key");
    Re.no_case (Re.str "api-key");
    Re.no_case (Re.str "apikey");
    Re.no_case (Re.str "token");
    Re.no_case (Re.str "secret");
    Re.no_case (Re.str "password");
    Re.no_case (Re.str "bearer");
  ]

let stop_chars = [ Re.space; Re.char '"'; Re.char ',';
                   Re.char '}'; Re.char ')'; Re.char ']' ]

let secret_re_kv =
  Re.compile (
    Re.seq [
      secret_kw;
      Re.rep (Re.alt
        [ Re.space; Re.char '"'; Re.char ':'; Re.char '=' ]);
      Re.alt [ Re.char ':'; Re.char '=' ];
      Re.rep (Re.alt [ Re.space; Re.char '"' ]);
      Re.rep1 (Re.compl stop_chars);
    ])

(* Bearer-style: "Bearer <value>" / "Token <value>" with whitespace. *)
let secret_re_bearer =
  Re.compile (
    Re.seq [
      Re.no_case (Re.alt [ Re.str "bearer"; Re.str "token" ]);
      Re.rep1 Re.space;
      Re.rep1 (Re.compl stop_chars);
    ])

(* Hashed API key pattern (e.g. sk-ant-...) — match any
   POISON-CANARY-shaped uppercase ALL-CAPS-with-DASHES-AND-DIGITS run
   that follows an API_KEY-shaped name. Already covered by [secret_re_kv]
   since [API_KEY=...] matches. *)

let scrub s =
  let s = Re.replace ~all:true secret_re_kv
            ~f:(fun _ -> "<scrubbed>") s in
  Re.replace ~all:true secret_re_bearer
    ~f:(fun _ -> "<scrubbed>") s

let now_iso () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  let ms = int_of_float ((t -. floor t) *. 1000.0) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec ms

let json_line ~level ~event ~details =
  let obj : Yojson.Safe.t = `Assoc [
    "ts",     `String (now_iso ());
    "level",  `String level;
    "event",  `String event;
    "details", details;
  ] in
  scrub (Yojson.Safe.to_string obj)

let append_jsonl t level event details =
  match t.jsonl_path with
  | None -> ()
  | Some path ->
      let line = json_line ~level ~event ~details in
      Persist.append_jsonl_line ~path ~line

let stderr_line t s =
  match t.verbosity with
  | `Quiet           -> ()
  | `Verbose | `Debug -> output_string stderr (scrub s ^ "\n"); flush stderr

(* H3 — Debug-only stderr line. Visible at [`Debug] verbosity only,
   so [-vv] is strictly additive over [-v]. Subprocess argv listings
   and agent prompt prefixes go through this channel. *)
let debug_line t s =
  match t.verbosity with
  | `Debug -> output_string stderr (scrub s ^ "\n"); flush stderr
  | _ -> ()

let debug t event details =
  append_jsonl t "debug" event details;
  debug_line t (Printf.sprintf "[debug] %s" event)

let info t event details =
  append_jsonl t "info" event details;
  stderr_line t (Printf.sprintf "[info] %s" event)

let warn t event details =
  append_jsonl t "warn" event details;
  (* Warnings always emit on stderr, regardless of verbosity, per error
     policy: warnings are user-visible signal. *)
  output_string stderr (scrub (Printf.sprintf "k4k: warning: %s\n" event));
  flush stderr

let error t err =
  let details : Yojson.Safe.t = `Assoc [
    "code", `String (Error.code_id err);
    "message", `String (Error.render err);
  ] in
  append_jsonl t "error" "error" details;
  (* User-facing line: ALWAYS on stderr (even at Quiet) per
     spec/error-taxonomy.md. *)
  output_string stderr
    (scrub (Printf.sprintf "k4k: %s\n" (Error.render err)));
  flush stderr

let stdout_line _t s =
  output_string stdout (s ^ "\n");
  flush stdout

(* Re-export [Tty_status] under a nested submodule so callers can use
   [Logger.Tty_status] per kb/plan.md#step-4. *)
module Tty_status = Tty_status
