(** [Config] — see [.mli]. *)

type t = {
  backend_command : string option;
}

let path ~k4k_dir = Filename.concat k4k_dir "config.json"

let on_path name =
  let r = Subprocess.run ~prog:"sh"
    ~args:[ "-c";
            Printf.sprintf "command -v %s >/dev/null 2>&1"
              (Filename.quote name) ]
    ~timeout_s:3 () in
  r.exit_code = 0

let autodetect_backend_command () =
  if on_path "claude_code_backend" then Some "claude_code_backend"
  else if on_path "ollama_backend" then Some "ollama_backend"
  else None

let json_string_of cmd =
  Yojson.Safe.to_string (`String cmd)

let render_default ?(backend = None) () =
  let cmd_field = match backend with
    | None -> "null"
    | Some s -> json_string_of s
  in
  Printf.sprintf
    {|{
  "_help": "k4k operator config — backend.command is a shell-style argv string for an executable conforming to kb/external/backend-protocol.md (examples: \"claude_code_backend\", \"/usr/local/bin/ollama_backend --model qwen3.5:9b\"). null disables the backend; the watcher will idle. K4K_BACKEND_COMMAND overrides this file. Auto-created at first run; safe to edit.",
  "backend": {
    "command": %s
  }
}
|} cmd_field

let parse_existing raw : t =
  match Yojson.Safe.from_string raw with
  | exception _ -> { backend_command = None }
  | `Assoc fields ->
      let backend_command =
        match List.assoc_opt "backend" fields with
        | Some (`Assoc bf) ->
            (match List.assoc_opt "command" bf with
             | Some (`String s) when s <> "" -> Some s
             | _ -> None)
        | _ -> None
      in
      { backend_command }
  | _ -> { backend_command = None }

let read_or_create ~k4k_dir : t =
  let p = path ~k4k_dir in
  if Sys.file_exists p then begin
    try parse_existing (Persist.read_file p)
    with _ -> { backend_command = None }
  end else begin
    let auto = autodetect_backend_command () in
    Persist.ensure_dir k4k_dir;
    let body = render_default ~backend:auto () in
    (try Persist.atomic_write ~path:p body with _ -> ());
    { backend_command = auto }
  end
