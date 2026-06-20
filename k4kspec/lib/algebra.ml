(* The blessed value algebra (v1 subset), as TOTAL, byte-first OCaml functions.
   Each function here is the audited-once reference semantics that a k4kspec spec
   is stated in terms of (the TCB at the statement level, per ADR-016 / spec/k4kspec.md).
   Bytes are OCaml [string] (8-bit clean). Every function is total. *)

(* ---- sequences over bytes -------------------------------------------------- *)

(* split b sep : mechanical, keeps EVERY piece (incl. a trailing empty).
   sep must be nonempty; split _ "" is defined as the whole string as one piece. *)
let split (b : string) (sep : string) : string list =
  if sep = "" then [ b ]
  else begin
    let n = String.length b and m = String.length sep in
    let rec go start acc =
      (* find sep at or after [start] *)
      let rec find i =
        if i + m > n then None
        else if String.sub b i m = sep then Some i
        else find (i + 1)
      in
      match find start with
      | None -> List.rev (String.sub b start (n - start) :: acc)
      | Some i -> go (i + m) (String.sub b start (i - start) :: acc)
    in
    go 0 []
  end

(* join xs sep : inverse of split for the common case. *)
let join (xs : string list) (sep : string) : string = String.concat sep xs

(* lines : the documented POSIX line convention. A final '\n' is a terminator,
   not an introducer of an empty trailing line.
     lines ""        = []
     lines "a\nb\n"  = ["a";"b"]
     lines "a\nb"    = ["a";"b"]
     lines "a\n\nb\n" = ["a";"";"b"]   *)
let lines (b : string) : string list =
  if b = "" then []
  else begin
    let parts = split b "\n" in
    (* drop a single trailing "" produced by a final '\n' *)
    match List.rev parts with
    | "" :: rest -> List.rev rest
    | _ -> parts
  end

(* unlines xs = join xs "\n" plus a trailing '\n' iff nonempty (inverse of lines). *)
let unlines (xs : string list) : string =
  match xs with [] -> "" | _ -> String.concat "\n" xs ^ "\n"

let contains (hay : string) (needle : string) : bool =
  if needle = "" then true
  else begin
    let n = String.length hay and m = String.length needle in
    let rec find i =
      if i + m > n then false
      else if String.sub hay i m = needle then true
      else find (i + 1)
    in
    find 0
  end

let starts_with (b : string) (p : string) : bool =
  let m = String.length p in
  String.length b >= m && String.sub b 0 m = p

let ends_with (b : string) (s : string) : bool =
  let n = String.length b and m = String.length s in
  n >= m && String.sub b (n - m) m = s

(* byte-wise ASCII case folding; bytes >= 128 untouched (faithfulness!). *)
let ascii_upper (b : string) : string =
  String.map (fun c -> if c >= 'a' && c <= 'z' then Char.chr (Char.code c - 32) else c) b

let ascii_lower (b : string) : string =
  String.map (fun c -> if c >= 'A' && c <= 'Z' then Char.chr (Char.code c + 32) else c) b

(* ---- list primitives (total) ---------------------------------------------- *)

let len (xs : 'a list) : int = List.length xs

let get (xs : 'a list) (i : int) (default : 'a) : 'a =
  match List.nth_opt xs i with Some v -> v | None -> default

let head (xs : 'a list) (default : 'a) : 'a =
  match xs with x :: _ -> x | [] -> default

let first (xs : 'a list) (p : 'a -> bool) (default : 'a) : 'a =
  match List.find_opt p xs with Some v -> v | None -> default

(* ---- parsing (total) ------------------------------------------------------ *)

let is_decimal (b : string) : bool =
  b <> "" && String.for_all (fun c -> c >= '0' && c <= '9') b

(* int_of : parse a decimal prefix; documented default 0 on non-decimal. *)
let int_of (b : string) : int =
  if is_decimal b then int_of_string b else 0
