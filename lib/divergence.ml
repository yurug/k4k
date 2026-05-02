(** Divergence-report builder for the two-run formalization protocol per
    [kb/properties/edge-cases.md#T10] and ADR-005. *)

type t = {
  run_a_id   : string;
  run_b_id   : string;
  hash_a     : string;
  hash_b     : string;
  diff_paths : string list;     (* JSON paths where the trees differ *)
}

(* Walk two yojson trees side-by-side, returning slash-delimited paths
   to the first ~few~ differing nodes. *)

let rec walk path acc (a : Yojson.Safe.t) (b : Yojson.Safe.t) =
  match a, b with
  | `Assoc xs, `Assoc ys ->
      let keys =
        let s = List.map fst xs @ List.map fst ys in
        List.sort_uniq String.compare s
      in
      List.fold_left (fun acc k ->
        let av = try List.assoc k xs with Not_found -> `Null in
        let bv = try List.assoc k ys with Not_found -> `Null in
        walk (path ^ "/" ^ k) acc av bv
      ) acc keys
  | `List xs, `List ys ->
      let n = max (List.length xs) (List.length ys) in
      let xa = Array.of_list xs and ya = Array.of_list ys in
      let rec loop i acc =
        if i >= n then acc
        else
          let av = if i < Array.length xa then xa.(i) else `Null in
          let bv = if i < Array.length ya then ya.(i) else `Null in
          loop (i + 1)
            (walk (Printf.sprintf "%s[%d]" path i) acc av bv)
      in
      loop 0 acc
  | _ ->
      if a = b then acc
      else path :: acc

let diff a b =
  let paths = List.rev (walk "" [] a b) in
  match paths with
  | [] -> [ "/" ]   (* hashes differ but JSON walk says equal — guard. *)
  | _ -> paths

let to_yojson (d : t) : Yojson.Safe.t =
  `Assoc [
    "run_a", `String d.run_a_id;
    "run_b", `String d.run_b_id;
    "hash_a", `String d.hash_a;
    "hash_b", `String d.hash_b;
    "diff_paths", `List (List.map (fun s -> `String s) d.diff_paths);
  ]
