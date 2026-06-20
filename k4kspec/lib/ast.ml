(* k4kspec AST (the subset the v1 oracle interprets).
   A spec denotes a relation R; here we evaluate the DETERMINED channels
   (stdout, exit) and carry a predicate for under-specified ones (stderr). *)

type value =
  | B of string                 (* bytes *)
  | I of int
  | Bool of bool
  | L of value list
  | Opt of value option

type expr =
  | Lit of value
  | Argv of int                 (* argv[i] (0-based positional; program name excluded) *)
  | ArgvAll                     (* the whole argv as a list of bytes *)
  | Stdin
  | FileBytes                   (* the single footprint file's content (assumes present) *)
  | Var of string               (* let- or lambda-bound *)
  | App of string * expr list   (* blessed primitive / builtin application *)
  | Lam of string * expr        (* \x -> body, only as a combinator argument *)
  | If of expr * expr * expr

type chan = Stdout | Stderr | Exit

type pred = OneNonemptyLine | Any | Nonempty | EmptyB

type rhs =
  | Eq of expr                  (* o.chan = expr   (pinned)        *)
  | P of pred                   (* predicate on o.chan (free part) *)

type case = {
  guard : expr option;          (* None = otherwise *)
  lets  : (string * expr) list; (* evaluated in order before outs *)
  outs  : (chan * rhs) list;
}

type footprint =
  | NoFiles
  | FileAt of int               (* reads: file at argv[i] *)
  | FileAtEach                  (* reads: file at each of argv[*]  (variadic) *)

(* an author-written example: the author's stated intent for one input.
   files lists the PRESENT files (path -> content); any path not listed is absent. *)
type example = {
  ex_argv   : string list;
  ex_files  : (string * string) list;
  ex_stdout : string option;    (* expected stdout (None = unchecked) *)
  ex_exit   : int option;       (* expected exit  (None = unchecked) *)
}

type spec = {
  name     : string;
  reads    : footprint;
  cases    : case list;         (* ordered, first-match; final case has guard=None *)
  examples : example list;
}
