(** Internal UTF-8 validator used by [Parser]. *)

let utf8_seq_length b0 =
  if b0 < 0x80 then 0
  else if b0 < 0xC2 then -1
  else if b0 < 0xE0 then 1
  else if b0 < 0xF0 then 2
  else if b0 < 0xF5 then 3
  else -1

let raise_enc off = raise (Error.K4k_error (Error.E_encoding off))

let validate_continuations s start n =
  for k = 1 to n do
    let cc = Char.code s.[start + k] in
    if cc < 0x80 || cc > 0xBF then raise_enc (start + k)
  done

(** [check s] raises [Error.K4k_error (E_encoding off)] on the first
    invalid byte. *)
let check s =
  let len = String.length s in
  let i = ref 0 in
  while !i < len do
    let b0 = Char.code s.[!i] in
    let need = utf8_seq_length b0 in
    if need < 0 || !i + need >= len then raise_enc !i;
    validate_continuations s !i need;
    i := !i + 1 + need
  done

let strip_bom s =
  let len = String.length s in
  if len >= 3 && s.[0] = '\xEF' && s.[1] = '\xBB' && s.[2] = '\xBF'
  then String.sub s 3 (len - 3)
  else s
