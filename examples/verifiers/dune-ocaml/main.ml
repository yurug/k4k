(** Reference verifier — OCaml + dune projects.

    Standalone binary that conforms to k4k's verifier wire protocol
    (see kb/external/verifier-protocol.md). It is NOT linked into k4k.

    Invocation:
      verify_dune_ocaml --workdir <dir> [--focus P1 P2 ...] --output <path>

    Behavior:
      - Runs `dune build @runtest --force --display=quiet --root <workdir>`
      - Parses alcotest output lines `[OK|FAIL]  <suite>  <num>  <name>.`
      - Maps test names matching `P<7hex>_<slug>` to property statuses
      - Writes the result JSON atomically (tmp + rename)
      - Exits 0 on result-written, 1 on tool error, 130 on SIGINT *)

open K4k

(* ---------- Alcotest output parser (ported from Dune_output) ---------- *)

type test_kind = [ `Ok | `Fail ]

type test_line = {
  kind        : test_kind;
  test_name   : string;
  property_id : string option;
}

let property_id_of_test_name (name : string) : string option =
  if String.length name < 9 then None
  else if name.[0] <> 'P' then None
  else
    match String.index_opt name '_' with
    | None -> None
    | Some i when i = 8 ->
        let pid = String.sub name 0 i in
        let valid = ref true in
        for j = 1 to i - 1 do
          let c = pid.[j] in
          if not ((c >= '0' && c <= '9')
                  || (c >= 'a' && c <= 'f')
                  || (c >= 'A' && c <= 'F'))
          then valid := false
        done;
        if !valid then Some pid else None
    | Some _ -> None

let trim_trailing_dot s =
  let n = String.length s in
  let rec last i =
    if i < 0 then -1
    else match s.[i] with
      | ' ' | '\t' | '\r' | '.' -> last (i - 1)
      | _ -> i
  in
  let i = last (n - 1) in
  if i < 0 then "" else String.sub s 0 (i + 1)

let parse_line (line : string) : test_line option =
  let trimmed = String.trim line in
  let kind =
    if Astring.String.is_prefix ~affix:"[OK]" trimmed then Some `Ok
    else if Astring.String.is_prefix ~affix:"[FAIL]" trimmed then Some `Fail
    else None
  in
  match kind with
  | None -> None
  | Some k ->
      let rest = match k with
        | `Ok -> String.sub trimmed 4 (String.length trimmed - 4)
        | `Fail -> String.sub trimmed 6 (String.length trimmed - 6)
      in
      let tokens =
        String.split_on_char ' ' rest
        |> List.filter (fun s -> s <> "")
      in
      (match tokens with
       | _suite :: num :: name_tokens
         when (try ignore (int_of_string num); true with _ -> false)
              && name_tokens <> [] ->
           let raw_name = String.concat " " name_tokens in
           let name = trim_trailing_dot raw_name in
           Some { kind = k;
                  test_name = name;
                  property_id = property_id_of_test_name name }
       | _ -> None)

let parse (output : string) : test_line list =
  String.split_on_char '\n' output
  |> List.filter_map parse_line

(* ---------- by_property + warnings construction ---------- *)

let kind_to_status = function
  | `Ok   -> "established"
  | `Fail -> "contradicted"

let merge_status acc (pid, st) =
  match List.assoc_opt pid acc with
  | None -> (pid, st) :: acc
  | Some prev ->
      let chosen = match prev, st with
        | "contradicted", _ | _, "contradicted" -> "contradicted"
        | _ -> st
      in
      (pid, chosen) :: List.remove_assoc pid acc

let dedup_by_property (lines : test_line list) =
  let recognized =
    List.filter_map (fun (l : test_line) ->
      match l.property_id with
      | Some pid -> Some (pid, kind_to_status l.kind)
      | None -> None) lines
  in
  List.fold_left merge_status [] recognized

let by_property_of_lines (lines : test_line list) ~focus =
  let dedup = dedup_by_property lines in
  if focus = [] then dedup
  else
    List.fold_left (fun acc pid ->
      match List.assoc_opt pid dedup with
      | Some s -> (pid, s) :: acc
      | None -> (pid, "unknown") :: acc) [] focus

let warnings_of_lines (lines : test_line list) =
  List.filter_map (fun (l : test_line) ->
    if l.property_id = None
    then Some (`Assoc [
      "kind", `String "unconventional-test-name";
      "message", `String l.test_name;
    ])
    else None) lines

(* ---------- argv parsing ---------- *)

type args = {
  workdir : string;
  focus   : string list;
  output  : string;
}

let parse_args argv =
  let n = Array.length argv in
  let workdir = ref "" in
  let output = ref "" in
  let focus = ref [] in
  let i = ref 1 in
  while !i < n do
    let a = argv.(!i) in
    (match a with
     | "--workdir" when !i + 1 < n ->
         workdir := argv.(!i + 1); i := !i + 2
     | "--output" when !i + 1 < n ->
         output := argv.(!i + 1); i := !i + 2
     | "--focus" ->
         (* All following non-flag tokens, until next flag or end. *)
         incr i;
         while !i < n && not (Astring.String.is_prefix ~affix:"--" argv.(!i)) do
           focus := argv.(!i) :: !focus;
           incr i
         done
     | _ -> incr i)
  done;
  { workdir = !workdir;
    focus = List.rev !focus;
    output = !output }

(* ---------- run dune ---------- *)

let dune_args ~workdir =
  ["build"; "@runtest"; "--force"; "--display=quiet";
   "--root"; workdir]

let run_dune ~workdir ~timeout_s =
  Subprocess.run ~prog:"dune" ~args:(dune_args ~workdir)
    ~timeout_s ()

(* ---------- result JSON ---------- *)

let result_json ~by_property ~raw_exit_code ~duration_ms ~warnings
    : Yojson.Safe.t =
  `Assoc [
    "by_property", `Assoc (List.map (fun (pid, s) ->
      (pid, `String s)) by_property);
    "raw_exit_code", `Int raw_exit_code;
    "duration_ms", `Int duration_ms;
    "warnings", `List warnings;
  ]

let atomic_write path content =
  Persist.atomic_write ~path content

let write_result ~output ~by_property ~raw_exit_code
    ~duration_ms ~warnings =
  let j = result_json ~by_property ~raw_exit_code ~duration_ms ~warnings in
  atomic_write output (Canonical_json.to_string j)

(* ---------- main ---------- *)

let interpret args (sub : Subprocess.result) =
  if sub.timed_out then
    (Printf.eprintf "verify_dune_ocaml: dune timed out\n"; 1)
  else if sub.exit_code = 130 then
    (Printf.eprintf "verify_dune_ocaml: dune interrupted\n"; 130)
  else
    let combined = sub.stdout ^ "\n" ^ sub.stderr in
    let lines = parse combined in
    if sub.exit_code = 1 && lines = [] then
      (Printf.eprintf "verify_dune_ocaml: dune build error\n"; 1)
    else if sub.exit_code >= 2 then
      (Printf.eprintf "verify_dune_ocaml: dune exited %d: %s\n"
         sub.exit_code (String.trim sub.stderr); 1)
    else begin
      let by_property = by_property_of_lines lines ~focus:args.focus in
      let warnings = warnings_of_lines lines in
      write_result ~output:args.output ~by_property
        ~raw_exit_code:sub.exit_code
        ~duration_ms:sub.duration_ms ~warnings;
      0
    end

let () =
  let args = parse_args Sys.argv in
  if args.workdir = "" || args.output = "" then begin
    Printf.eprintf
      "usage: verify_dune_ocaml --workdir <dir> [--focus P1 ...] --output <path>\n";
    exit 1
  end;
  match run_dune ~workdir:args.workdir ~timeout_s:300 with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) ->
      Printf.eprintf "verify_dune_ocaml: dune binary not found\n";
      exit 1
  | sub ->
      exit (interpret args sub)
