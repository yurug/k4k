type issue = { section : string; line : int option; details : string }

type error =
  | E_format               of { line : int; col : int; reason : string }
  | E_unstable             of issue list
  | E_version              of { found : int; supported : int list }
  | E_class_unsupported    of string
  | E_budget               of { used : int; cap : int }
  | E_max_steps            of int
  | E_agent_unavailable    of string
  | E_verifier_unavailable of string
  | E_verifier_tool_error  of string
  | E_disk_full            of string
  | E_state_corrupt        of string
  | E_encoding             of int
  | E_file_not_found       of string
  | E_file_too_large       of int

exception K4k_error of error
exception Invariant_violation of string

let issue ?line ~section details = { section; line; details }

let code_id = function
  | E_format _               -> "EFORMAT"
  | E_unstable _             -> "EUNSTABLE"
  | E_version _              -> "EVERSION"
  | E_class_unsupported _    -> "ECLASS_UNSUPPORTED"
  | E_budget _               -> "EBUDGET"
  | E_max_steps _            -> "EMAXSTEPS"
  | E_agent_unavailable _    -> "EAGENT_UNAVAILABLE"
  | E_verifier_unavailable _ -> "EVERIFIER_UNAVAILABLE"
  | E_verifier_tool_error _  -> "EVERIFIER_TOOL_ERROR"
  | E_disk_full _            -> "EDISK_FULL"
  | E_state_corrupt _        -> "ESTATE_CORRUPT"
  | E_encoding _             -> "EENCODING"
  | E_file_not_found _       -> "EFILE_NOT_FOUND"
  | E_file_too_large _       -> "EFILE_TOO_LARGE"

let exit_code_of = function
  (* User errors (1) — interaction file issues. *)
  | E_format _ | E_unstable _ | E_version _
  | E_class_unsupported _ | E_encoding _
  | E_file_not_found _ | E_file_too_large _ -> 1
  (* Verifier errors (2). *)
  | E_verifier_unavailable _ | E_verifier_tool_error _ -> 2
  (* Agent errors (3). *)
  | E_agent_unavailable _ -> 3
  (* Resource exhaustion (4). *)
  | E_budget _ | E_max_steps _ | E_disk_full _ -> 4
  (* Environment / state (5). *)
  | E_state_corrupt _ -> 5

let render_issues lst =
  match lst with
  | []       -> "no specific issue reported"
  | _        ->
      let one i =
        let where = match i.line with
          | Some n -> Printf.sprintf "%s:%d" i.section n
          | None   -> i.section
        in
        Printf.sprintf "%s: %s" where i.details
      in
      String.concat "; " (List.map one lst)

let render_input_errors = function
  | E_format { line; col; reason } ->
      Printf.sprintf "format error: %d:%d: %s" line col reason
  | E_unstable issues ->
      Printf.sprintf "unstable: %s" (render_issues issues)
  | E_version { found; supported } ->
      let sup = String.concat "," (List.map string_of_int supported) in
      Printf.sprintf "unsupported version: %d (this k4k handles versions %s)"
        found sup
  | E_class_unsupported c ->
      Printf.sprintf "unsupported class: %s (v0 supports: cli)" c
  | E_encoding off ->
      Printf.sprintf "encoding error at byte %d: invalid UTF-8 sequence" off
  | E_file_not_found p ->
      Printf.sprintf "file not found: %s" p
  | E_file_too_large n ->
      Printf.sprintf "file too large: %d bytes (max 10485760)" n
  | _ -> assert false

let render_resource_errors = function
  | E_budget { used; cap } ->
      Printf.sprintf "budget exhausted: %d/%d units; .k4k/ left consistent"
        used cap
  | E_max_steps n ->
      Printf.sprintf "max steps reached (%d)" n
  | E_disk_full p ->
      Printf.sprintf "disk full while writing %s; rolled back" p
  | _ -> assert false

let render_external_errors = function
  | E_agent_unavailable d ->
      Printf.sprintf "agent backend unavailable: %s" d
  | E_verifier_unavailable d ->
      Printf.sprintf "verifier unavailable: %s" d
  | E_verifier_tool_error d ->
      Printf.sprintf "verifier error: %s" d
  | E_state_corrupt d ->
      Printf.sprintf "state corrupt: %s; consider --reset" d
  | _ -> assert false

let render = function
  | E_format _ | E_unstable _ | E_version _ | E_class_unsupported _
  | E_encoding _ | E_file_not_found _ | E_file_too_large _ as e ->
      render_input_errors e
  | E_budget _ | E_max_steps _ | E_disk_full _ as e ->
      render_resource_errors e
  | E_agent_unavailable _ | E_verifier_unavailable _
  | E_verifier_tool_error _ | E_state_corrupt _ as e ->
      render_external_errors e
