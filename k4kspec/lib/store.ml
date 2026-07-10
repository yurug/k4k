(* Store — the <name>.k4k/ sidecar LEDGER next to a spec file. Tool-owned; the two human
   artifacts (<name>.k4kspec, <name>.hints) stay as plain sibling files. Everything here
   uses basenames in cross-references so the triple is `git mv`-able as a unit. *)

let strip_ext p = Filename.remove_extension p

(* greet.k4kspec -> greet.k4k, greet.hints, greet.k4kspec.new *)
let ledger_dir spec_path = strip_ext spec_path ^ ".k4k"
let hints_path spec_path = strip_ext spec_path ^ ".hints"
let new_spec_path spec_path = spec_path ^ ".new"
let new_hints_path spec_path = hints_path spec_path ^ ".new"

let signatures_dir sp = Filename.concat (ledger_dir sp) "signatures"
let proposals_dir sp = Filename.concat (ledger_dir sp) "proposals"
let certificates_dir sp v = Filename.concat (Filename.concat (ledger_dir sp) "certificates") (Printf.sprintf "v%d" v)
let decisions_path sp = Filename.concat (ledger_dir sp) "decisions.md"
let last_failure_path sp = Filename.concat (ledger_dir sp) "last-failure.md"

let rec ensure_dir d =
  if not (Sys.file_exists d) then begin
    ensure_dir (Filename.dirname d);
    (try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
  end

let read_file p =
  let ic = open_in_bin p in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let write_file p s =
  ensure_dir (Filename.dirname p);
  let oc = open_out_bin p in output_string oc s; close_out oc

(* ledger records are never overwritten *)
let write_new p s =
  if Sys.file_exists p then failwith (Printf.sprintf "store: refusing to overwrite %s" p);
  write_file p s

(* highest v<N>.sig in the signatures dir *)
let latest_signature spec_path : (int * string) option =
  let dir = signatures_dir spec_path in
  if not (Sys.file_exists dir) then None
  else
    Array.fold_left
      (fun acc f ->
        match Scanf.sscanf_opt f "v%d.sig%!" (fun n -> n) with
        | Some n when (match acc with Some (m, _) -> n > m | None -> true) ->
            Some (n, Filename.concat dir f)
        | _ -> acc)
      None (Sys.readdir dir)

let timestamp () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
    t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

(* proposals/<ts>-<kind>.md ; timestamps are filesystem-safe *)
let proposal_path spec_path kind =
  let ts = String.map (function ':' -> '-' | c -> c) (timestamp ()) in
  Filename.concat (proposals_dir spec_path) (Printf.sprintf "%s-%s.md" ts kind)

(* copy named files from a certify workdir into certificates/v<N>/ *)
let promote spec_path version (files : (string * string) list) =
  let dst = certificates_dir spec_path version in
  ensure_dir dst;
  List.iter
    (fun (src, name) ->
      if Sys.file_exists src then begin
        write_file (Filename.concat dst name) (read_file src);
        (* the certified binary (extension-less) stays executable *)
        if Filename.extension name = "" then (try Unix.chmod (Filename.concat dst name) 0o755 with _ -> ())
      end)
    files;
  dst
