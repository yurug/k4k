(** [Cotype_stub] — in-memory deterministic stub for tests.

    Mirrors the [Cotype] surface; does NOT shell out. Tests that don't
    need real cotype semantics (no diff3 merge) use this stub; the S1
    and T8 integration tests use the real [Cotype] against the cotype
    binary. *)

type config = {
  binary : string;
  conflict_on_save : bool;
  fixed_version    : string;
}

let default_config = {
  binary = "<stub:cotype>";
  conflict_on_save = false;
  fixed_version = "0.0.0-stub";
}

type entry = {
  mutable bytes  : string;
  mutable bases  : (string * string) list;  (* sha -> bytes *)
}

type t = {
  cfg : config;
  files : (string, entry) Hashtbl.t;
}

let name = "cotype-stub"

let create cfg = { cfg; files = Hashtbl.create 4 }

let version t = t.cfg.fixed_version

let sha_of bytes = "sha256:" ^ Persist.sha256_hex bytes

let read_or_empty path =
  if Sys.file_exists path then Persist.read_file path else ""

let ensure_entry t ~file =
  match Hashtbl.find_opt t.files file with
  | Some e -> e
  | None ->
      let b = read_or_empty file in
      let e = { bytes = b; bases = [(sha_of b, b)] } in
      Hashtbl.add t.files file e; e

let init t ~file =
  let _e = ensure_entry t ~file in
  Ok ()

let ensure_init = init

type open_result = {
  base_sha   : string;
  base_path  : string;
  conflicted : bool;
}

(* Write the base snapshot to a per-file path under a deterministic
   sidecar dir; this gives Persist.append_clarification a real path
   to read from, exercising the "read from base_path" rule. *)
let write_base ~file ~sha bytes =
  let dir = Printf.sprintf "%s.cotype-stub" file in
  Persist.ensure_dir dir;
  let path = Filename.concat dir sha in
  Persist.atomic_write ~path bytes;
  path

let open_ t ~file =
  let e = ensure_entry t ~file in
  let sha = sha_of e.bytes in
  if not (List.mem_assoc sha e.bases) then
    e.bases <- (sha, e.bytes) :: e.bases;
  let path = write_base ~file ~sha e.bytes in
  Ok { base_sha = sha; base_path = path; conflicted = false }

type save_outcome =
  | Direct   of string
  | Merged   of string
  | Noop
  | Conflict of { conflict_path : string }

let save t ~file ~base_sha ~actor:_ ~bytes =
  let e = ensure_entry t ~file in
  let cur_sha = sha_of e.bytes in
  if t.cfg.conflict_on_save then begin
    let cp = Printf.sprintf "%s.cotype-stub/conflict" file in
    Persist.atomic_write ~path:cp bytes;
    Ok (Conflict { conflict_path = cp })
  end else if cur_sha = base_sha then begin
    if bytes = e.bytes then Ok Noop
    else begin
      let new_sha = sha_of bytes in
      e.bytes <- bytes;
      e.bases <- (new_sha, bytes) :: e.bases;
      Persist.atomic_write ~path:file bytes;
      Ok (Direct new_sha)
    end
  end else begin
    (* Stale base. Without a real diff3, conservatively report
       conflict; tests that need merged semantics use the real
       Cotype against the cotype binary. *)
    let cp = Printf.sprintf "%s.cotype-stub/conflict-%s" file base_sha in
    Persist.atomic_write ~path:cp bytes;
    Ok (Conflict { conflict_path = cp })
  end

let status t ~file =
  match Hashtbl.find_opt t.files file with
  | None -> Ok `Unmanaged
  | Some _ -> Ok `Clean
