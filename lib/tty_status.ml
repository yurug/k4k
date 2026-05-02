(** [Tty_status] — single-line in-place TTY status renderer.

    See [tty_status.mli] for the contract and [kb/plan.md#step-4]. *)

let max_window = 10

type window = {
  samples : float list;       (* most-recent first *)
  count   : int;
}

let empty_window () = { samples = []; count = 0 }

let push_duration w secs =
  let xs = secs :: w.samples in
  let xs = if w.count >= max_window then
             List.filteri (fun i _ -> i < max_window) xs
           else xs in
  let n = if w.count >= max_window then max_window else w.count + 1 in
  { samples = xs; count = n }

let median w =
  match w.samples with
  | [] -> None
  | _ ->
      let sorted = List.sort compare w.samples in
      let n = w.count in
      let mid = n / 2 in
      let pick i = List.nth sorted i in
      if n mod 2 = 1 then Some (pick mid)
      else Some ((pick (mid - 1) +. pick mid) /. 2.0)

let eta_of w ~remaining =
  match median w with
  | None -> None
  | Some m -> Some (m *. float_of_int (max 0 remaining))

let format_eta secs =
  let s = max 0 (int_of_float (Float.round secs)) in
  let m = s / 60 in
  let r = s mod 60 in
  Printf.sprintf "%dm%02ds" m r

let bar ~progress =
  let p = max 0 (min 8 progress) in
  let filled = String.make p '#' in
  let empty = String.make (8 - p) '_' in
  filled ^ empty

let render ~step ~total ~property_id ~slug ~progress ~eta =
  let eta_s = match eta with
    | None -> "--"
    | Some s -> format_eta s in
  Printf.sprintf "[k4k] step %d/%d \xe2\x80\xa2 %s (%s) \xe2\x80\xa2 agent %s \xe2\x80\xa2 ETA %s"
    step total property_id slug (bar ~progress) eta_s

let is_tty () =
  try Unix.isatty Unix.stdout with _ -> false

let print_inplace s =
  (* CR + ANSI EL (clear to end of line) + payload, no newline. *)
  output_string stdout "\r\027[K";
  output_string stdout s;
  flush stdout

let print_final_newline () =
  output_char stdout '\n';
  flush stdout
