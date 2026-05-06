(** [Clarification] — pure helpers for the cotype-mediated
    clarification-append flow (ADR-010). The concrete cotype binding
    lives in [Cotype.append_clarification]; this module owns the
    pure splice + the cotype-agnostic seam used by tests. *)

let timestamp_of_now () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02d-%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

let render_section ~timestamp ~questions =
  let buf = Buffer.create 256 in
  Buffer.add_string buf "## k4k:clarification:";
  Buffer.add_string buf timestamp;
  Buffer.add_char buf '\n';
  List.iter (fun q ->
    Buffer.add_string buf "- "; Buffer.add_string buf q;
    Buffer.add_char buf '\n') questions;
  Buffer.contents buf

(* Splice: append a fresh `## k4k:clarification:<ts>` section to
   [base_bytes]. We never rewrite existing sections — pre-existing
   bytes pass through verbatim, satisfying P1. *)
let splice ~base_bytes ~timestamp ~questions =
  let block = render_section ~timestamp ~questions in
  let n = String.length base_bytes in
  let needs_nl = n > 0 && base_bytes.[n - 1] <> '\n' in
  if needs_nl then base_bytes ^ "\n" ^ block
  else base_bytes ^ block

type cotype_open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

type cotype_save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

let raise_state_corrupt_conflict ~conflict_path =
  raise (Error.K4k_error
    (Error.E_state_corrupt
       (Printf.sprintf
          "interaction file conflict: cotype reported overlapping edits; \
           see %s; resolve diff3 markers in your editor and run \
           `cotype resolve <file>` before re-running k4k"
          conflict_path)))

let raise_cotype_error msg =
  raise (Error.K4k_error
    (Error.E_state_corrupt (Printf.sprintf "cotype error: %s" msg)))

let append_via ~ensure_init ~open_ ~save ~path ~questions =
  (match ensure_init ~file:path with
   | Ok () -> ()
   | Error msg -> raise_cotype_error msg);
  let opened : cotype_open_result =
    match open_ ~file:path with
    | Ok r -> r
    | Error msg -> raise_cotype_error msg
  in
  let base_bytes = Persist.read_file opened.base_path in
  let proposed = splice ~base_bytes
    ~timestamp:(timestamp_of_now ()) ~questions in
  match save ~file:path ~base_sha:opened.base_sha
          ~actor:"agent:k4k" ~bytes:proposed with
  | Ok (Direct _ | Merged _ | Noop) -> ()
  | Ok (Conflict { conflict_path }) ->
      raise_state_corrupt_conflict ~conflict_path
  | Error msg -> raise_cotype_error msg
