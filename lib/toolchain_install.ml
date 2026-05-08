(** [Toolchain_install] — see [.mli]. ADR-012 §7. *)

type package_manager =
  | Opam              of string
  | Pipx              of string
  | Uv_tool           of string
  | Cargo             of string
  | Npm               of string
  | System            of string
  | Other_user_install of string

type install_outcome =
  | Already_present of { binary : string; version : string }
  | Installed       of { binary : string; version : string; via : string }
  | Needs_user_consent of { binary : string;
                            reason : string;
                            suggested_command : string list option }
  | Failed          of string

(* ADR-012 §7: registry. ≤ 30 entries; documented in
   [kb/external/toolchain-install.md]. Adding a tool is a one-line
   change here — no logic edit, no new branch. *)
let mapping : (string * package_manager) list = [
  (* Rocq / Coq family *)
  "coqc",            Opam "coq";
  "coqtop",          Opam "coq";
  "coq-extraction",  Opam "coq";
  (* Frama-C / WP *)
  "frama-c",         Opam "frama-c";
  (* Lean 4 *)
  "lean",            Other_user_install "elan";
  "lake",            Other_user_install "elan";
  (* Verus / Rust verifiers *)
  "verus",           Cargo "verus";
  (* F* (system-only on most distros) *)
  "fstar.exe",       System "fstar";
  (* OCaml / dune ecosystem (used as a Tier-A backstop) *)
  "dune",            Opam "dune";
  "ocamlfind",       Opam "ocamlfind";
  "ocaml",           System "ocaml";
  (* Python-side scientific verifiers *)
  "z3",              Pipx "z3-solver";
  "cvc5",            Other_user_install "cvc5-binary";
  (* uv-side tools *)
  "ruff",            Uv_tool "ruff";
  "mypy",            Uv_tool "mypy";
  (* Cargo-side tools *)
  "rustup",          Other_user_install "rustup";
  "cargo",           Other_user_install "rustup";
  (* npm-side TS verifiers *)
  "tsc",             Npm "typescript";
  (* k4k's own dev sidecars *)
  "cotype",          Other_user_install "cotype";
]

(* --- test-only stub table --- *)

let stub_table : (string, install_outcome) Hashtbl.t = Hashtbl.create 8

let test_set_stub_outcome ~binary outcome =
  Hashtbl.replace stub_table binary outcome

let test_reset_stubs () = Hashtbl.clear stub_table

let stub_active () =
  match Sys.getenv_opt "K4K_TOOLCHAIN_INSTALL_STUB" with
  | Some _ -> true | None -> false

(* --- helpers --- *)

let trim s =
  let n = String.length s in
  let rec last i =
    if i < 0 then -1
    else match s.[i] with
      | ' ' | '\t' | '\n' | '\r' -> last (i - 1)
      | _ -> i
  in
  let i = last (n - 1) in
  if i < 0 then "" else String.sub s 0 (i + 1)

let probe_binary binary : (string, unit) result =
  let r = Subprocess.run ~prog:"sh"
    ~args:["-c";
           Printf.sprintf
             "command -v %s 2>/dev/null && %s --version 2>&1 || true"
             (Filename.quote binary) (Filename.quote binary)]
    ~timeout_s:5 () in
  if r.exit_code <> 0 then Error ()
  else
    let out = trim r.stdout in
    if out = "" then Error ()
    else
      (* First line is the path (from [command -v]); the rest is the
         version banner. We surface the full banner trimmed. *)
      let lines = String.split_on_char '\n' out in
      match lines with
      | [] | [_] -> Ok (List.fold_left (fun a l -> a ^ l) "" lines)
      | _ :: rest -> Ok (String.concat " " (List.map trim rest))

let pkg_manager_command pm =
  match pm with
  | Opam pkg              -> Some ("opam", ["install"; "-y"; pkg], "opam")
  | Pipx pkg              -> Some ("pipx", ["install"; pkg], "pipx")
  | Uv_tool pkg           -> Some ("uv", ["tool"; "install"; pkg], "uv")
  | Cargo pkg             -> Some ("cargo", ["install"; "--locked"; pkg],
                                   "cargo")
  | Npm pkg               ->
      let prefix = Filename.concat (Sys.getenv "HOME")
        ".local/share/k4k/npm" in
      Some ("npm", ["install"; "-g"; "--prefix"; prefix; pkg], "npm")
  | System _              -> None
  | Other_user_install _  -> None

let pm_binary_present pm =
  match pkg_manager_command pm with
  | None -> false
  | Some (prog, _, _) ->
      let r = Subprocess.run ~prog:"sh"
        ~args:["-c"; Printf.sprintf "command -v %s >/dev/null 2>&1"
                       (Filename.quote prog)] ~timeout_s:3 () in
      r.exit_code = 0

let suggest_for binary pm =
  match pm with
  | System pkg ->
      Some [ "sudo"; "<system-package-manager>"; "install"; pkg ]
  | Other_user_install hint ->
      Some [ "see"; "kb/external/toolchain-install.md";
             "for"; binary; "via"; hint ]
  | Opam pkg ->
      Some [ "bash"; "-c";
             Printf.sprintf
               "(opam install -y %s) || curl -fsSL \
                https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh | sh"
               pkg ]
  | _ -> None

let run_install binary pm =
  match pkg_manager_command pm with
  | None ->
      Needs_user_consent { binary;
        reason = "package manager requires sudo or manual install";
        suggested_command = suggest_for binary pm; }
  | Some (prog, args, via) ->
      if not (pm_binary_present pm) then
        Needs_user_consent { binary;
          reason = Printf.sprintf
            "%s package-manager binary not found on PATH" via;
          suggested_command = suggest_for binary pm; }
      else
        let r = Subprocess.run ~prog ~args ~timeout_s:600 () in
        if r.exit_code <> 0 then
          Failed (Printf.sprintf "%s install %s failed: %s"
                    via binary (trim r.stderr))
        else
          (match probe_binary binary with
           | Ok ver -> Installed { binary; version = ver; via }
           | Error () ->
               Failed (Printf.sprintf
                 "%s reported success but %s still not on PATH"
                 via binary))

let ensure ~binary : install_outcome =
  if stub_active () then
    match Hashtbl.find_opt stub_table binary with
    | Some o -> o
    | None -> Failed (Printf.sprintf "stub: no outcome for %s" binary)
  else
    match probe_binary binary with
    | Ok ver -> Already_present { binary; version = ver }
    | Error () ->
        match List.assoc_opt binary mapping with
        | None ->
            Needs_user_consent { binary;
              reason = "binary not in toolchain-install registry";
              suggested_command = None; }
        | Some pm -> run_install binary pm
