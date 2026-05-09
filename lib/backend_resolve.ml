(** [Backend_resolve] — see [.mli]. *)

type emit_fn = string -> Yojson.Safe.t -> unit

let split_command (s : string) : string list =
  let n = String.length s in
  let buf = Buffer.create 32 in
  let acc = ref [] in
  let in_q = ref false in
  let i = ref 0 in
  let flush () =
    if Buffer.length buf > 0 then begin
      acc := Buffer.contents buf :: !acc;
      Buffer.clear buf
    end
  in
  while !i < n do
    let c = s.[!i] in
    (match c with
     | '"' -> in_q := not !in_q; incr i
     | '\\' when !in_q && !i + 1 < n ->
         Buffer.add_char buf s.[!i + 1]; i := !i + 2
     | ' ' | '\t' when not !in_q -> flush (); incr i
     | _ -> Buffer.add_char buf c; incr i)
  done;
  flush ();
  List.rev !acc

let canned_invoke ~emit ~path : Version_loop.agent_invoke =
  match Backend_canned.load_from_path path with
  | Error msg ->
      emit "agent.canned_load_error"
        (`Assoc [ "error", `String msg ]);
      fun ~purpose:_ ~prompt:_ ~budget:_ ->
        `Tool_error ("canned load: " ^ msg)
  | Ok t -> Backend_canned.invoke t

let external_invoke ~emit ~cmd : Version_loop.agent_invoke =
  let argv = split_command cmd in
  match argv with
  | [] ->
      emit "agent.misconfigured"
        (`Assoc [ "reason",
                  `String "K4K_BACKEND_COMMAND is empty after split" ]);
      fun ~purpose:_ ~prompt:_ ~budget:_ ->
        `Tool_error "K4K_BACKEND_COMMAND empty"
  | _ ->
      let cfg = { Backend_external.default_config with
                  command = argv } in
      let t = Backend_external.create cfg in
      emit "agent.external_configured"
        (`Assoc [ "command",
                  `List (List.map (fun s -> `String s) argv) ]);
      Backend_external.invoke t

let unconfigured ~emit ~k4k_dir : Version_loop.agent_invoke =
  let cfg_path = Config.path ~k4k_dir in
  emit "agent.unconfigured"
    (`Assoc [ "hint",
              `String (Printf.sprintf
                "edit %s and set backend.command to a wire-protocol \
                 backend (e.g. \"claude_code_backend\"), \
                 or set K4K_BACKEND_COMMAND" cfg_path) ]);
  fun ~purpose:_ ~prompt:_ ~budget:_ ->
    `Tool_error "no agent backend configured"

let resolve ~emit ~k4k_dir : Version_loop.agent_invoke =
  match Sys.getenv_opt "K4K_STUB_RESPONSES" with
  | Some path when path <> "" -> canned_invoke ~emit ~path
  | _ ->
      (match Sys.getenv_opt "K4K_BACKEND_COMMAND" with
       | Some cmd when cmd <> "" -> external_invoke ~emit ~cmd
       | _ ->
           let cfg = Config.read_or_create ~k4k_dir in
           (match cfg.backend_command with
            | Some cmd -> external_invoke ~emit ~cmd
            | None -> unconfigured ~emit ~k4k_dir))
