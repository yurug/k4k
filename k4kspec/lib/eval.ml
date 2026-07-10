(* The spec oracle: evaluate a k4kspec [spec] on a concrete input, producing the
   DETERMINED channels (stdout, exit) and the constraint on the free one (stderr).
   This is the executable semantics used for differential validation. *)

open Ast

type input = {
  argv : string list;
  stdin : string;
  read_file : string -> string option;   (* path -> content, None if absent *)
}

type stderr_c = SExact of string | SPred of pred

type result = { rstdout : string; rexit : int; rstderr : stderr_c }

exception Spec_error of string

(* the input MATCHED case [idx], but that case's stdout/exit is a predicate (law-constrained /
   under-determined) — the oracle cannot produce THE output because the spec admits several.
   NOT an error: certify proves the implementation satisfies the laws; the oracle just cannot
   cross-check it. Distinguished from Spec_error so reports stop calling this "no case matched". *)
exception Undetermined of int

(* ---- value coercions ------------------------------------------------------ *)
let to_b = function B s -> s | _ -> raise (Spec_error "expected bytes")
let to_i = function I n -> n | _ -> raise (Spec_error "expected int")
let to_bool = function Bool b -> b | _ -> raise (Spec_error "expected bool")
let to_list = function L xs -> xs | _ -> raise (Spec_error "expected list")

let footprint_file (sp : spec) (inp : input) : string option =
  match sp.reads with
  | FileAt i -> (match List.nth_opt inp.argv i with Some p -> inp.read_file p | None -> None)
  | _ -> None

(* ---- expression evaluation ------------------------------------------------ *)
let rec eval (sp : spec) (inp : input) (env : (string * value) list) (e : expr) : value =
  let ev = eval sp inp env in
  match e with
  | Lit v -> v
  | Argv i -> B (match List.nth_opt inp.argv i with Some s -> s | None -> "")
  | ArgvAll -> L (List.map (fun s -> B s) inp.argv)
  | Stdin -> B inp.stdin
  | FileBytes -> B (Option.value ~default:"" (footprint_file sp inp))
  | Var x -> (try List.assoc x env with Not_found -> raise (Spec_error ("unbound " ^ x)))
  | If (c, a, b) -> if to_bool (ev c) then ev a else ev b
  | Lam _ -> raise (Spec_error "lambda only valid as a combinator argument")
  | OStdout | OStderr | OExit -> raise (Spec_error "output reference only valid in a relational law")
  | App (f, args) -> apply sp inp env f args

and apply_lam sp inp env lam v =
  match lam with
  | Lam (x, body) -> eval sp inp ((x, v) :: env) body
  | _ -> raise (Spec_error "expected lambda")

and apply sp inp env f args : value =
  let ev = eval sp inp env in
  let b1 () = to_b (ev (List.nth args 0)) in
  let b2 () = to_b (ev (List.nth args 1)) in
  match f, args with
  (* logic / comparison *)
  | "not", [a] -> Bool (not (to_bool (ev a)))
  | "and", [a; b] -> Bool (to_bool (ev a) && to_bool (ev b))
  | "or", [a; b] -> Bool (to_bool (ev a) || to_bool (ev b))
  | "eq", [a; b] -> Bool (ev a = ev b)
  | "ne", [a; b] -> Bool (ev a <> ev b)
  | "lt", [a; b] -> Bool (to_i (ev a) < to_i (ev b))
  | "le", [a; b] -> Bool (to_i (ev a) <= to_i (ev b))
  | "gt", [a; b] -> Bool (to_i (ev a) > to_i (ev b))
  | "ge", [a; b] -> Bool (to_i (ev a) >= to_i (ev b))
  | "add", [a; b] -> I (to_i (ev a) + to_i (ev b))
  | "sub", [a; b] -> I (to_i (ev a) - to_i (ev b))
  (* sizes / emptiness *)
  | "len", [a] -> (match ev a with B s -> I (String.length s) | L xs -> I (List.length xs) | _ -> raise (Spec_error "len"))
  | "is_empty", [a] -> (match ev a with L xs -> Bool (xs = []) | B s -> Bool (s = "") | _ -> Bool false)
  (* bytes *)
  | "concat", [_; _] -> B (b1 () ^ b2 ())
  | "contains", [_; _] -> Bool (Algebra.contains (b1 ()) (b2 ()))
  | "starts_with", [_; _] -> Bool (Algebra.starts_with (b1 ()) (b2 ()))
  | "ends_with", [_; _] -> Bool (Algebra.ends_with (b1 ()) (b2 ()))
  | "split", [_; _] -> L (List.map (fun s -> B s) (Algebra.split (b1 ()) (b2 ())))
  | "join", [a; b] -> B (Algebra.join (List.map to_b (to_list (ev a))) (to_b (ev b)))
  | "lines", [_] -> L (List.map (fun s -> B s) (Algebra.lines (b1 ())))
  | "unlines", [a] -> B (Algebra.unlines (List.map to_b (to_list (ev a))))
  | "ascii_upper", [_] -> B (Algebra.ascii_upper (b1 ()))
  | "ascii_lower", [_] -> B (Algebra.ascii_lower (b1 ()))
  | "is_decimal", [_] -> Bool (Algebra.is_decimal (b1 ()))
  | "int_of", [_] -> I (Algebra.int_of (b1 ()))
  (* list access *)
  | "get", [a; b; d] -> Algebra.get (to_list (ev a)) (to_i (ev b)) (ev d)
  | "head", [a; d] -> Algebra.head (to_list (ev a)) (ev d)
  | "first", [a; lam; d] -> Algebra.first (to_list (ev a)) (fun v -> to_bool (apply_lam sp inp env lam v)) (ev d)
  (* combinators (2nd arg is a lambda) *)
  | "filter", [a; lam] -> L (List.filter (fun v -> to_bool (apply_lam sp inp env lam v)) (to_list (ev a)))
  | "map", [a; lam] -> L (List.map (fun v -> apply_lam sp inp env lam v) (to_list (ev a)))
  | "any", [a; lam] -> Bool (List.exists (fun v -> to_bool (apply_lam sp inp env lam v)) (to_list (ev a)))
  | "all", [a; lam] -> Bool (List.for_all (fun v -> to_bool (apply_lam sp inp env lam v)) (to_list (ev a)))
  | "count", [a; lam] -> I (List.length (List.filter (fun v -> to_bool (apply_lam sp inp env lam v)) (to_list (ev a))))
  | "fold", [a; init; lam2] ->
      (* fold(xs, init, \acc x -> body) : lam2 is a 2-arg lambda encoded as nested Lam *)
      List.fold_left
        (fun acc x ->
          match lam2 with
          | Lam (accv, Lam (xv, body)) -> eval sp inp ((xv, x) :: (accv, acc) :: env) body
          | _ -> raise (Spec_error "fold expects \\acc x -> body"))
        (ev init) (to_list (ev a))
  (* filesystem (footprint) *)
  | "absent_footprint", [] -> Bool (footprint_file sp inp = None)
  | "present_footprint", [] -> Bool (footprint_file sp inp <> None)
  | "file_at", [a] -> Opt (Option.map (fun c -> B c) (inp.read_file (to_b (ev a))))
  | "absent", [a] -> (match ev a with Opt o -> Bool (o = None) | _ -> raise (Spec_error "absent"))
  | "opt_bytes", [a] -> (match ev a with Opt (Some v) -> v | Opt None -> B "" | _ -> raise (Spec_error "opt_bytes"))
  | _ -> raise (Spec_error (Printf.sprintf "unknown builtin %s/%d" f (List.length args)))

(* ---- predicate check ------------------------------------------------------ *)
let one_nonempty_line (s : string) : bool =
  s <> "" && (match String.index_opt s '\n' with
              | None -> true                          (* no newline: one line *)
              | Some i -> i = String.length s - 1)    (* exactly one trailing newline *)

let check_pred (p : pred) (s : string) : bool =
  match p with
  | OneNonemptyLine -> one_nonempty_line s
  | Nonempty -> s <> ""
  | EmptyB -> s = ""
  | Any -> true

(* ---- run the spec (first-match case) -------------------------------------- *)
let eval_case (sp : spec) (inp : input) (c : case) : result =
  let env = List.fold_left (fun env (x, e) -> (x, eval sp inp env e) :: env) [] c.lets in
  let out chan = List.assoc chan c.outs in
  let get_b chan = match out chan with Eq e -> to_b (eval sp inp env e) | P _ -> raise (Spec_error "stdout must be pinned") in
  let get_i chan = match out chan with Eq e -> to_i (eval sp inp env e) | P _ -> raise (Spec_error "exit must be pinned") in
  let stderr = match out Stderr with Eq e -> SExact (to_b (eval sp inp env e)) | P p -> SPred p in
  { rstdout = get_b Stdout; rexit = get_i Exit; rstderr = stderr }

(* run, also returning the index of the matched case (for dead-case detection) *)
let run_traced (sp : spec) (inp : input) : result * int =
  let rec pick idx = function
    | [] -> raise (Spec_error "non-exhaustive spec (no matching case)")
    | c :: rest ->
        let matches = match c.guard with None -> true | Some g -> to_bool (eval sp inp [] g) in
        if matches then (c, idx) else pick (idx + 1) rest
  in
  let c, idx = pick 0 sp.cases in
  let undet =
    List.exists (fun (ch, r) -> (ch = Stdout || ch = Exit) && (match r with P _ -> true | Eq _ -> false)) c.outs
  in
  if undet then raise (Undetermined idx);
  (eval_case sp inp c, idx)

let run (sp : spec) (inp : input) : result = fst (run_traced sp inp)

(* convenience: an [input] backed by an in-memory file map *)
let input_of ?(stdin = "") (argv : string list) (files : (string * string) list) : input =
  { argv; stdin; read_file = (fun p -> List.assoc_opt p files) }
