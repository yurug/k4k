(** Stable property-ID generator per [kb/spec/algorithms.md#property-ids].

    The ID is [P || sha256(aspect_path | length-prefixed)[:7]] where
    [aspect_path] is a list of strings (e.g. ["errors";"EBADARG";"when"]).
    Each path element is encoded as [<len-decimal> <colon> <bytes>] so
    the boundary between elements is unambiguous. *)

let encode_path (path : string list) : string =
  let buf = Buffer.create 32 in
  List.iter (fun s ->
    Buffer.add_string buf (string_of_int (String.length s));
    Buffer.add_char buf ':';
    Buffer.add_string buf s
  ) path;
  Buffer.contents buf

let of_path (path : string list) : string =
  let h = Persist.sha256_hex (encode_path path) in
  let short = String.sub h 0 7 in
  "P" ^ short
