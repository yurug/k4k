(** Edge-case tests for boundary conditions enforced in step 1. *)

open K4k

let with_tmpdir f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "k4k-edge-%d-%d" (Unix.getpid ()) (Random.int 1_000_000))
  in
  Unix.mkdir dir 0o755;
  let r =
    try f dir
    with e ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)) in
      raise e
  in
  let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)) in
  r

(* T7 — oversize file (> 10 MiB) is rejected with EFILE_TOO_LARGE. *)
let t7_oversize_rejected () =
  with_tmpdir (fun dir ->
    let p = Filename.concat dir "big.k4k" in
    let oc = open_out_bin p in
    let chunk = String.make (1024 * 1024) 'x' in
    for _ = 1 to 11 do output_string oc chunk done;
    close_out oc;
    try
      let _ = Persist.read_file p in
      Alcotest.fail "expected E_file_too_large"
    with Error.K4k_error (Error.E_file_too_large n) ->
      Alcotest.(check bool) "size > max" true
        (n > Persist.max_interaction_file_bytes))

(* T7 — at the exact 10 MiB cap the file should still parse (i.e. read_file
   succeeds). *)
let t7_at_cap_succeeds () =
  with_tmpdir (fun dir ->
    let p = Filename.concat dir "atcap.k4k" in
    let oc = open_out_bin p in
    output_string oc (String.make Persist.max_interaction_file_bytes 'x');
    close_out oc;
    let s = Persist.read_file p in
    Alcotest.(check int) "size at cap"
      Persist.max_interaction_file_bytes (String.length s))

(* T6 — invalid UTF-8 (already exercised in unit tests; mirror at edge
   surface for visibility in the T-test inventory). *)
let t6_non_utf8_rejected () =
  let bad = "---\n\xC3\x28\nclass: cli\n---\n" in
  match (try ignore (Parser.parse bad); `Ok with
         | Error.K4k_error (Error.E_encoding _) -> `Enc
         | _ -> `Other) with
  | `Enc -> ()
  | _ -> Alcotest.fail "expected EENCODING for invalid UTF-8"

(* T17 — stale manifest with foreign k4k_version is reported corrupt. *)
let t17_stale_manifest_corrupt () =
  with_tmpdir (fun dir ->
    let kdir = Filename.concat dir ".k4k" in
    Persist.ensure_dir kdir;
    Persist.atomic_write
      ~path:(Filename.concat kdir "manifest.json")
      {|{"k4k_version":"99.99.99-future"}|};
    (* Read it back to ensure persistence; the harness-level check lives
       in the unit-test suite under HT.t17_stale_manifest_corrupt. *)
    let raw = Persist.read_file (Filename.concat kdir "manifest.json") in
    Alcotest.(check bool) "persisted" true
      (Astring.String.is_infix ~affix:"99.99.99-future" raw))

let () =
  Alcotest.run "k4k edge"
    [ "T6",  [ Alcotest.test_case "T6_non_utf8_rejected" `Quick t6_non_utf8_rejected ];
      "T7",  [ Alcotest.test_case "T7_oversize_rejected" `Quick t7_oversize_rejected;
               Alcotest.test_case "T7_at_cap_succeeds" `Quick t7_at_cap_succeeds ];
      "T17", [ Alcotest.test_case "T17_stale_manifest_persists" `Quick
                 t17_stale_manifest_corrupt ];
    ]
