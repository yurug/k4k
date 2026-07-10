(* Sign — the certification anchor. A signature record pins the EXACT bytes of a reviewed
   spec (BLAKE256), records the under-spec acknowledgment (ADR-016 §12) and any tier waivers
   (PRD S3: written, with rationale), and numbers the version. Any byte change to the spec
   invalidates it. certify/certify-agent GATE on a valid signature (the propose/review UX's
   "k4k develops only what was signed"). *)

type waiver = { case_i : int; law_j : int; tier : string; rationale : string }

type signature = {
  spec_file : string;                (* basename *)
  spec_hash : string;
  hints_file : string option;
  hints_hash : string option;        (* informational — ADR-017 certificate invariance *)
  version : int;
  previous : string;                 (* "none" or "v<N> <hash>" *)
  date : string;
  signer : string;
  underspec : string list;
  waivers : waiver list;
}

let hash_bytes (s : string) : string = Digest.BLAKE256.to_hex (Digest.BLAKE256.string s)
let hash_file (p : string) : string = hash_bytes (Store.read_file p)

(* "case#<i>.law#<j>:<B|C>" *)
let parse_waiver_ref (s : string) : (int * int * string, string) result =
  match Scanf.sscanf_opt s "case#%d.law#%d:%s%!" (fun i j t -> (i, j, t)) with
  | Some (i, j, (("B" | "C") as t)) when i >= 0 && j >= 0 -> Ok (i, j, t)
  | Some (_, _, t) -> Error (Printf.sprintf "waiver tier must be B or C (got %S); pinned channels are never waivable" t)
  | None -> Error (Printf.sprintf "bad waiver reference %S (expected case#<i>.law#<j>:<B|C>)" s)

(* validate refs against the parsed spec: case in range, law in range *)
let validate_waivers (sp : Ast.spec) (ws : (int * int * string * string) list) : (unit, string) result =
  let ncases = List.length sp.Ast.cases in
  let rec go = function
    | [] -> Ok ()
    | (i, j, _, _) :: rest ->
        if i < 0 || i >= ncases then Error (Printf.sprintf "case#%d does not exist (spec has %d case(s))" i ncases)
        else
          let c = List.nth sp.Ast.cases i in
          let nlaws = List.length c.Ast.laws in
          if j < 0 || j >= nlaws then
            Error (Printf.sprintf "case#%d.law#%d does not exist (case#%d has %d law(s))" i j i nlaws)
          else go rest
  in
  go ws

(* the single choke point: strip waived laws BEFORE elaboration (all three certify modes).
   Check still sees the full spec — a waiver is certification scope, not a spec edit. *)
let apply_waivers (sp : Ast.spec) (ws : (int * int) list) : Ast.spec =
  { sp with
    Ast.cases =
      List.mapi
        (fun i (c : Ast.case) ->
          { c with Ast.laws = List.filteri (fun j _ -> not (List.mem (i, j) ws)) c.Ast.laws })
        sp.Ast.cases }

(* ---- record encoding -------------------------------------------------------- *)

let to_record (s : signature) : Record.t =
  let waiver_fields =
    List.concat_map
      (fun w ->
        [ ("waive", Printf.sprintf "case#%d.law#%d tier=%s" w.case_i w.law_j w.tier);
          ("rationale", w.rationale) ])
      s.waivers
  in
  { Record.fields =
      [ ("k4k-signature", "1"); ("spec", s.spec_file); ("spec-sha256", s.spec_hash) ]
      @ (match s.hints_file, s.hints_hash with
         | Some f, Some h -> [ ("hints", f); ("hints-sha256", h) ]
         | _ -> [ ("hints", "none") ])
      @ [ ("version", string_of_int s.version); ("previous", s.previous);
          ("date", s.date); ("signer", s.signer) ]
      @ List.map (fun u -> ("underspec", u)) s.underspec
      @ waiver_fields;
    sections = [] }

let of_record (r : Record.t) : (signature, string) result =
  let req k = match Record.get r k with Some v -> Ok v | None -> Error ("signature record missing " ^ k) in
  match req "spec", req "spec-sha256", req "version" with
  | Ok spec_file, Ok spec_hash, Ok v ->
      (* pair waive/rationale fields in order *)
      let waivers = ref [] and pending = ref None in
      List.iter
        (fun (k, value) ->
          match k, !pending with
          | "waive", _ ->
              (match Scanf.sscanf_opt value "case#%d.law#%d tier=%s%!" (fun i j t -> (i, j, t)) with
               | Some (i, j, t) -> pending := Some (i, j, t)
               | None -> ())
          | "rationale", Some (i, j, t) ->
              waivers := { case_i = i; law_j = j; tier = t; rationale = value } :: !waivers;
              pending := None
          | _ -> ())
        r.Record.fields;
      Ok
        { spec_file; spec_hash;
          hints_file = (match Record.get r "hints" with Some "none" | None -> None | f -> f);
          hints_hash = Record.get r "hints-sha256";
          version = int_of_string v;
          previous = Option.value (Record.get r "previous") ~default:"none";
          date = Option.value (Record.get r "date") ~default:"";
          signer = Option.value (Record.get r "signer") ~default:"";
          underspec = Record.get_all r "underspec";
          waivers = List.rev !waivers }
  | Error e, _, _ | _, Error e, _ | _, _, Error e -> Error e

(* ---- sign ------------------------------------------------------------------- *)

type sign_error = { msg : string; code : int }

let sign ~(spec_path : string) ~(ack_underspec : bool)
    ~(waivers : (int * int * string * string) list) : (int * string, sign_error) result =
  if not (Sys.file_exists spec_path) then Error { msg = spec_path ^ " does not exist"; code = 2 }
  else
    let src = Store.read_file spec_path in
    match Parse.parse src with
    | exception Parse.Parse_error m -> Error { msg = "parse error: " ^ m; code = 2 }
    | sp -> (
        let ok, report = Check.report sp in
        if not ok then
          Error { msg = report ^ "\nREFUSE: check failed — a spec that fails check cannot be signed."; code = 1 }
        else
          match validate_waivers sp waivers with
          | Error m -> Error { msg = "REFUSE: " ^ m; code = 2 }
          | Ok () ->
              let free = Check.free_dims sp in
              let underspec =
                List.map
                  (fun (i, ch, pr) ->
                    Printf.sprintf "case#%d %s %s ACKNOWLEDGED" i (Check.chan_name ch) (Check.pred_name pr))
                  free
              in
              if free <> [] && not ack_underspec then
                Error
                  { msg =
                      String.concat "\n"
                        (List.map (fun (i, ch, pr) ->
                             Printf.sprintf "  case#%d %s : free (%s)" i (Check.chan_name ch) (Check.pred_name pr))
                           free)
                      ^ Printf.sprintf
                          "\nREFUSE: this spec leaves %d observable dimension(s) unconstrained (listed above).\n\
                           Signing acknowledges them as INTENDED. Re-run with --ack-underspec to sign."
                          (List.length free);
                    code = 4 }
              else begin
                let spec_hash = hash_bytes src in
                let hints_p = Store.hints_path spec_path in
                let hints_file, hints_hash =
                  if Sys.file_exists hints_p then (Some (Filename.basename hints_p), Some (hash_file hints_p))
                  else (None, None)
                in
                let ws = List.map (fun (i, j, t, r) -> { case_i = i; law_j = j; tier = t; rationale = r }) waivers in
                let same_waivers (a : waiver list) (b : waiver list) =
                  List.map (fun w -> (w.case_i, w.law_j, w.tier)) a
                  = List.map (fun w -> (w.case_i, w.law_j, w.tier)) b
                in
                match Store.latest_signature spec_path with
                | Some (n, path) when
                    (match of_record (Record.of_string (Store.read_file path)) with
                     | Ok prev -> prev.spec_hash = spec_hash && same_waivers prev.waivers ws
                     | Error _ -> false) ->
                    Ok (n, path)   (* idempotent: unchanged spec + waivers *)
                | latest ->
                    let version, previous =
                      match latest with
                      | Some (n, path) ->
                          let prev_hash =
                            match of_record (Record.of_string (Store.read_file path)) with
                            | Ok p -> p.spec_hash | Error _ -> "?"
                          in
                          (n + 1, Printf.sprintf "v%d %s" n prev_hash)
                      | None -> (1, "none")
                    in
                    let s =
                      { spec_file = Filename.basename spec_path; spec_hash; hints_file; hints_hash;
                        version; previous; date = Store.timestamp ();
                        signer = (match Sys.getenv_opt "K4K_SIGNER" with Some s -> s | None -> Option.value (Sys.getenv_opt "USER") ~default:"unknown");
                        underspec; waivers = ws }
                    in
                    let path = Filename.concat (Store.signatures_dir spec_path) (Printf.sprintf "v%d.sig" version) in
                    Store.write_new path (Record.to_string (to_record s));
                    Ok (version, path)
              end)

(* ---- the certify gate --------------------------------------------------------- *)

type verdict = Valid of signature * string (* sig, path *) | Unsigned | Mismatch of string

(* verify against a GIVEN buffer — the caller hashes and parses THE SAME BYTES (the 2026-07-10
   audit found a read-twice TOCTOU when the gate hashed one read and the loader parsed another) *)
let verify_bytes ~(spec_path : string) ~(bytes : string) : verdict =
  match Store.latest_signature spec_path with
  | None -> Unsigned
  | Some (_, path) -> (
      match of_record (Record.of_string (Store.read_file path)) with
      | Error m -> Mismatch (Printf.sprintf "%s is unreadable: %s" path m)
      | Ok s ->
          let now = hash_bytes bytes in
          if now = s.spec_hash then Valid (s, path)
          else
            Mismatch
              (Printf.sprintf
                 "signature v%d pins sha256 %s but %s now hashes to %s — the spec changed after signing.\n\
                  Re-review and re-sign (k4kspec sign %s creates v%d)."
                 s.version (String.sub s.spec_hash 0 12) (Filename.basename spec_path)
                 (String.sub now 0 12) (Filename.basename spec_path) (s.version + 1)))

(* convenience for status display etc. — one fresh read; certify paths MUST use verify_bytes *)
let verify (spec_path : string) : verdict =
  verify_bytes ~spec_path ~bytes:(Store.read_file spec_path)
