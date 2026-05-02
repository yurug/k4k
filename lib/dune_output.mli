(** [Dune_output] — pure parser for alcotest test-output lines per
    [kb/external/dune.md]. *)

type test_kind = [ `Ok | `Fail ]

type test_line = {
  kind        : test_kind;
  test_name   : string;
  property_id : string option;   (** [None] iff the test name does not
                                     match [P<id>_<slug>] (T20). *)
}

(** [property_id_of_test_name n] returns [Some "P<7hex>"] when [n] starts
    with [P<7-hex-chars>_], else [None]. *)
val property_id_of_test_name : string -> string option

(** [parse_line l] parses one line of alcotest output; [None] on
    non-matching lines (headers, blanks, summaries). *)
val parse_line : string -> test_line option

(** [parse output] parses every line; returns recognized test entries. *)
val parse : string -> test_line list

(** [build_error_p output] is true iff the output contains no
    [OK]/[FAIL] lines (per external/dune.md, this disambiguates exit-1
    test-fail from exit-1 build error). *)
val build_error_p : string -> bool
