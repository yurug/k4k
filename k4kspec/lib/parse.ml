(* Surface parser: a .k4kspec text file -> Ast.spec.
   Grammar (v1, line-oriented; newlines and ';' separate statements):

     interface cli "NAME":
       reads:  (nothing | file at argv[i] | file at each of argv[*])
       writes: nothing
       env:    <ids>                      # parsed and ignored (not modelled yet)
     cases (on <ids>)?:
       when <expr>: <stmt> (; <stmt>)*    # inline
       otherwise:                         # or block (stmts on following lines)
         let x = <expr>
         stdout: <rhs>
         stderr: <rhs>
         exit:   <expr>
     examples:
       argv=[..] (file="..." | files={p="..",..})? -> stdout="..." exit=N

   A <rhs> is: `one nonempty line` | `nonempty` | `any` | <expr>.
   Every case must set stdout, stderr and exit exactly once. *)

open Ast

exception Parse_error of string

(* ---- lexer ---------------------------------------------------------------- *)
type tok =
  | TInt of int | TStr of string | TId of string
  | TLParen | TRParen | TLBrack | TRBrack | TLBrace | TRBrace
  | TComma | TColon | TSemi | TDot | TStar | TEq | TBackslash | TArrow
  | TEqEq | TNe | TLt | TLe | TGt | TGe | TConcat | TPlus | TMinus
  | TNewline | TEof

let lex (src : string) : (tok * int * int) list =
  let n = String.length src and toks = ref [] and i = ref 0 in
  let line = ref 1 and bol = ref 0 in
  let emit t sl sc = toks := (t, sl, sc) :: !toks in
  let peekc k = if !i + k < n then src.[!i + k] else '\000' in
  let is_id c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' || (c >= '0' && c <= '9') in
  let read_string () =
    incr i; (* opening quote *)
    let b = Buffer.create 16 in
    let rec go () =
      if !i >= n then raise (Parse_error "unterminated string literal");
      match src.[!i] with
      | '"' -> incr i
      | '\\' ->
          incr i;
          (match src.[!i] with
           | 'n' -> Buffer.add_char b '\n'; incr i
           | 't' -> Buffer.add_char b '\t'; incr i
           | 'r' -> Buffer.add_char b '\r'; incr i
           | '\\' -> Buffer.add_char b '\\'; incr i
           | '"' -> Buffer.add_char b '"'; incr i
           | '0' -> Buffer.add_char b '\000'; incr i
           | 'x' -> Buffer.add_char b (Char.chr (int_of_string ("0x" ^ String.sub src (!i + 1) 2))); i := !i + 3
           | c -> Buffer.add_char b c; incr i);
          go ()
      | c -> Buffer.add_char b c; incr i; go ()
    in
    go (); Buffer.contents b
  in
  while !i < n do
    let c = src.[!i] in
    if c = ' ' || c = '\t' || c = '\r' then incr i
    else if c = '\n' then (emit TNewline !line (!i - !bol + 1); incr i; incr line; bol := !i)
    else if c = '#' then (while !i < n && src.[!i] <> '\n' do incr i done)
    else begin
      let sl = !line and sc = !i - !bol + 1 in
      let t =
        if c = '"' then TStr (read_string ())
        else if c >= '0' && c <= '9' then begin
          let s = !i in while !i < n && src.[!i] >= '0' && src.[!i] <= '9' do incr i done;
          TInt (int_of_string (String.sub src s (!i - s)))
        end
        else if is_id c then begin
          let s = !i in while !i < n && is_id src.[!i] do incr i done;
          TId (String.sub src s (!i - s))
        end
        else
          (match c, peekc 1 with
           | '(', _ -> incr i; TLParen
           | ')', _ -> incr i; TRParen
           | '[', _ -> incr i; TLBrack
           | ']', _ -> incr i; TRBrack
           | '{', _ -> incr i; TLBrace
           | '}', _ -> incr i; TRBrace
           | ',', _ -> incr i; TComma
           | ':', _ -> incr i; TColon
           | ';', _ -> incr i; TSemi
           | '.', _ -> incr i; TDot
           | '*', _ -> incr i; TStar
           | '\\', _ -> incr i; TBackslash
           | '+', '+' -> i := !i + 2; TConcat
           | '+', _ -> incr i; TPlus
           | '-', '>' -> i := !i + 2; TArrow
           | '-', _ -> incr i; TMinus
           | '=', '=' -> i := !i + 2; TEqEq
           | '=', _ -> incr i; TEq
           | '!', '=' -> i := !i + 2; TNe
           | '<', '=' -> i := !i + 2; TLe
           | '<', _ -> incr i; TLt
           | '>', '=' -> i := !i + 2; TGe
           | '>', _ -> incr i; TGt
           | _ -> raise (Parse_error (Printf.sprintf "line %d col %d: unexpected character %C" sl sc c)))
      in
      emit t sl sc
    end
  done;
  emit TEof !line (!i - !bol + 1);
  List.rev !toks

(* ---- parser state --------------------------------------------------------- *)
type st = { toks : (tok * int * int) array; mutable pos : int }

let mk toks = { toks = Array.of_list toks; pos = 0 }
let cur st = st.toks.(st.pos)
let peek st = let t, _, _ = cur st in t
let peek2 st = if st.pos + 1 < Array.length st.toks then (let t, _, _ = st.toks.(st.pos + 1) in t) else TEof
let loc st = let _, l, c = cur st in Printf.sprintf "line %d col %d" l c
let adv st = st.pos <- st.pos + 1
let err st m = raise (Parse_error (Printf.sprintf "%s: %s" (loc st) m))
let eat st t = if peek st = t then adv st else err st "unexpected token"
let skip_nl st = while peek st = TNewline do adv st done
let id st = match peek st with TId s -> adv st; s | _ -> err st "expected identifier"
let kw st s = match peek st with TId k when k = s -> adv st | _ -> err st ("expected '" ^ s ^ "'")
let int_lit st = match peek st with TInt n -> adv st; n | _ -> err st "expected an integer"
let str_lit st = match peek st with TStr s -> adv st; s | _ -> err st "expected a string"

(* ---- expressions ---------------------------------------------------------- *)
let rec p_expr st : expr =
  match peek st with
  | TId "if" -> adv st; let c = p_expr st in kw st "then"; let a = p_expr st in kw st "else"; let b = p_expr st in If (c, a, b)
  | _ -> p_or st

and p_or st = let l = p_and st in if peek st = TId "or" then (adv st; App ("or", [ l; p_or st ])) else l
and p_and st = let l = p_cmp st in if peek st = TId "and" then (adv st; App ("and", [ l; p_and st ])) else l
and p_cmp st =
  let l = p_concat st in
  let op = match peek st with
    | TEqEq -> Some "eq" | TNe -> Some "ne" | TLt -> Some "lt"
    | TLe -> Some "le" | TGt -> Some "gt" | TGe -> Some "ge" | _ -> None in
  (match op with Some f -> adv st; App (f, [ l; p_concat st ]) | None -> l)
and p_concat st = let l = p_add st in if peek st = TConcat then (adv st; App ("concat", [ l; p_concat st ])) else l
and p_add st =
  let rec go l = match peek st with
    | TPlus -> adv st; go (App ("add", [ l; p_unary st ]))
    | TMinus -> adv st; go (App ("sub", [ l; p_unary st ]))
    | _ -> l
  in go (p_unary st)
and p_unary st = if peek st = TId "not" then (adv st; App ("not", [ p_unary st ])) else p_postfix st
and p_postfix st =
  let e = p_primary st in
  if peek st = TDot then (adv st; kw st "bytes"; App ("opt_bytes", [ e ])) else e
and p_primary st : expr =
  match peek st with
  | TInt n -> adv st; Lit (I n)
  | TStr s -> adv st; Lit (B s)
  | TLParen -> adv st; let e = p_expr st in eat st TRParen; e
  | TBackslash ->
      adv st;
      let rec params acc = match peek st with TId x -> adv st; params (x :: acc) | TArrow -> adv st; List.rev acc | _ -> err st "bad lambda parameters" in
      let ps = params [] in
      let body = p_expr st in
      List.fold_right (fun x b -> Lam (x, b)) ps body
  | TId "argv" -> adv st; if peek st = TLBrack then (adv st; let n = int_lit st in eat st TRBrack; Argv n) else ArgvAll
  | TId "stdin" -> adv st; Stdin
  | TId "true" -> adv st; Lit (Bool true)
  | TId "false" -> adv st; Lit (Bool false)
  | TId "file" ->
      adv st;
      (match peek st with
       | TDot -> adv st; kw st "bytes"; FileBytes
       | TId "absent" -> adv st; App ("absent_footprint", [])
       | TId "present" -> adv st; App ("present_footprint", [])
       | _ -> err st "expected 'file.bytes' / 'file absent' / 'file present'")
  | TId name -> adv st; if peek st = TLParen then App (name, p_args st) else Var name
  | _ -> err st "expected an expression"
and p_args st : expr list =
  eat st TLParen;
  if peek st = TRParen then (adv st; [])
  else begin
    let rec go acc =
      let a = p_expr st in
      match peek st with
      | TComma -> adv st; go (a :: acc)
      | TRParen -> adv st; List.rev (a :: acc)
      | _ -> err st "expected ',' or ')'"
    in go []
  end

(* ---- rhs / statements / cases --------------------------------------------- *)
let p_rhs st : rhs =
  match peek st with
  | TId "one" -> adv st; kw st "nonempty"; kw st "line"; P OneNonemptyLine
  | TId "nonempty" -> adv st; P Nonempty
  | TId "any" when peek2 st <> TLParen -> adv st; P Any
  | _ -> Eq (p_expr st)

let p_case st : case =
  let guard =
    match peek st with
    | TId "when" -> adv st; let g = p_expr st in eat st TColon; Some g
    | TId "otherwise" -> adv st; eat st TColon; None
    | _ -> err st "expected 'when' or 'otherwise'"
  in
  let lets = ref [] and outs = ref [] in
  let is_boundary () = match peek st with
    | TEof | TId "when" | TId "otherwise" | TId "examples" -> true | _ -> false in
  let rec loop () =
    while peek st = TSemi || peek st = TNewline do adv st done;
    if is_boundary () then ()
    else begin
      (match peek st with
       | TId "let" -> adv st; let x = id st in eat st TEq; let e = p_expr st in lets := (x, e) :: !lets
       | TId "stdout" -> adv st; eat st TColon; outs := (Stdout, p_rhs st) :: !outs
       | TId "stderr" -> adv st; eat st TColon; outs := (Stderr, p_rhs st) :: !outs
       | TId "exit" -> adv st; (if peek st = TColon then adv st); outs := (Exit, Eq (p_expr st)) :: !outs
       | _ -> err st "expected let / stdout: / stderr: / exit:");
      loop ()
    end
  in
  loop ();
  let find ch = match List.assoc_opt ch !outs with
    | Some r -> r
    | None -> err st (Printf.sprintf "case is missing a %s constraint"
        (match ch with Stdout -> "stdout" | Stderr -> "stderr" | Exit -> "exit")) in
  { guard; lets = List.rev !lets; outs = [ (Stdout, find Stdout); (Stderr, find Stderr); (Exit, find Exit) ] }

(* ---- footprint / examples / spec ------------------------------------------ *)
let p_footprints st : footprint =
  let reads = ref NoFiles in
  let rec loop () =
    skip_nl st;
    match peek st with
    | TId "reads" ->
        adv st; eat st TColon;
        (match peek st with
         | TId "nothing" -> adv st; reads := NoFiles
         | TId "file" ->
             adv st; kw st "at";
             (match peek st with
              | TId "each" -> adv st; kw st "of"; kw st "argv";
                  if peek st = TLBrack then (adv st; (if peek st = TStar then adv st); eat st TRBrack);
                  reads := FileAtEach
              | TId "argv" -> adv st; eat st TLBrack; let n = int_lit st in eat st TRBrack; reads := FileAt n
              | _ -> err st "expected 'argv[i]' or 'each of argv[*]'")
         | _ -> err st "expected 'nothing' or 'file at ...'");
        loop ()
    | TId "writes" -> adv st; eat st TColon; kw st "nothing"; loop ()   (* v1: specs write nothing *)
    | TId "env" -> adv st; eat st TColon; while peek st <> TNewline && peek st <> TEof do adv st done; loop ()
    | _ -> ()
  in
  loop (); !reads

let p_examples st (fp : footprint) : example list =
  if peek st <> TId "examples" then []
  else begin
    adv st; eat st TColon; skip_nl st;
    let exs = ref [] in
    while peek st = TId "argv" do
      adv st; eat st TEq; eat st TLBrack;
      let argv = ref [] in
      if peek st <> TRBrack then begin
        argv := [ str_lit st ];
        while peek st = TComma do adv st; argv := str_lit st :: !argv done
      end;
      eat st TRBrack;
      let argv = List.rev !argv in
      let files = ref [] in
      (match peek st with
       | TId "file" ->
           adv st; eat st TEq; let c = str_lit st in
           (match fp with
            | FileAt i -> (match List.nth_opt argv i with
                           | Some p -> files := [ (p, c) ]
                           | None -> err st "file= : the footprint argument is missing from argv")
            | _ -> err st "file= needs a single-file footprint; use files={..} instead")
       | TId "files" ->
           adv st; eat st TEq; eat st TLBrace;
           if peek st <> TRBrace then begin
             let one () = let p = str_lit st in eat st TEq; let c = str_lit st in files := (p, c) :: !files in
             one (); while peek st = TComma do adv st; one () done
           end;
           eat st TRBrace
       | _ -> ());
      eat st TArrow;
      let ex_stdout = ref None and ex_exit = ref None in
      let rec res () = match peek st with
        | TId "stdout" -> adv st; eat st TEq; ex_stdout := Some (str_lit st); res ()
        | TId "exit" -> adv st; eat st TEq; ex_exit := Some (int_lit st); res ()
        | TComma -> adv st; res ()
        | _ -> ()
      in
      res ();
      exs := { ex_argv = argv; ex_files = List.rev !files; ex_stdout = !ex_stdout; ex_exit = !ex_exit } :: !exs;
      skip_nl st
    done;
    List.rev !exs
  end

let parse (src : string) : spec =
  let st = mk (lex src) in
  skip_nl st;
  kw st "interface"; kw st "cli";
  let name = str_lit st in
  eat st TColon;
  let reads = p_footprints st in
  skip_nl st;
  kw st "cases";
  if peek st = TId "on" then (adv st; let rec sk () = match peek st with TColon | TEof -> () | _ -> adv st; sk () in sk ());
  eat st TColon;
  let cases = ref [] in
  skip_nl st;
  while peek st = TId "when" || peek st = TId "otherwise" do
    cases := p_case st :: !cases;
    skip_nl st
  done;
  let examples = p_examples st reads in
  { name; reads; cases = List.rev !cases; examples }
