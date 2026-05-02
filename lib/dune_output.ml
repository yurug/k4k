(** [Dune_output] — pure parser for alcotest test output per
    [kb/external/dune.md]. No I/O. *)

type test_kind = [ `Ok | `Fail ]

type test_line = {
  kind        : test_kind;
  test_name   : string;
  property_id : string option;  (* None when name doesn't match conv *)
}

(** Extract property ID prefix [P<7hex>] from a test name [P<id>_<slug>].
    Returns [None] if the convention is not met (T20). *)
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

(* Strip trailing dot and whitespace. *)
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

(** Parse one alcotest output line.
    Format: ["  [OK]   <suite>   <num>   <test_name>."]
    Returns [None] for non-matching lines. *)
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
      (* Drop the [OK]/[FAIL] tag. *)
      let rest = match k with
        | `Ok -> String.sub trimmed 4 (String.length trimmed - 4)
        | `Fail -> String.sub trimmed 6 (String.length trimmed - 6)
      in
      (* Tokenize on whitespace. We expect: <suite> <num> <name>... *)
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

(** Parse the full alcotest output. Returns the list of recognized
    [[OK]/[FAIL]] lines. *)
let parse (output : string) : test_line list =
  String.split_on_char '\n' output
  |> List.filter_map parse_line

(** [build_error_p output] is true iff the output contains no
    [OK]/[FAIL] test lines — implies a build / typecheck failure
    (per external/dune.md). *)
let build_error_p (output : string) : bool =
  parse output = []
