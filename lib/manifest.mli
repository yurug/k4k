(** [Manifest] — read/write/inspect [.k4k/manifest.json] per
    [kb/spec/data-model.md#manifest].

    The on-disk shape is JSON. This module exposes typed accessors
    (user-section hashes, cached desired hash) and a JSON builder for
    atomic-write callers. *)

(** An in-memory manifest. [None] means the file is absent. *)
type t

(** [path k4k_dir] = "[k4k_dir]/manifest.json". *)
val path : string -> string

(** [k4k_version_string] — the version string this build writes
    into [k4k_version]. *)
val k4k_version_string : string

(** [read_or_init ~k4k_dir] — reads the manifest at
    [k4k_dir/manifest.json]. Returns [None] if the file is absent.

    @raise Error.K4k_error E_state_corrupt on version mismatch or
                           unparseable JSON. *)
val read_or_init : k4k_dir:string -> t

(** [user_section_hashes m] — keyed map from user-section id to body
    sha256 stored in [interaction_file.last_user_section_hashes]. *)
val user_section_hashes : t -> (string * string) list

(** [desired_hash m] — the cached canonical hash of [D], if any. *)
val desired_hash : t -> string option

(** [build ...] — assembles a manifest JSON value, ready to be
    [Yojson.Safe.pretty_to_string]'d and atomically written. The
    optional [verifier_command] records the exact command line used
    so audits can reconstruct the invocation. *)
val build :
  ?verifier_command:string list ->
  file_path:string ->
  file_sha256:string ->
  user_section_hashes:(string * string) list ->
  agent_name:string ->
  agent_version:string ->
  verifier_name:string ->
  verifier_version:string ->
  desired_hash:string ->
  unit ->
  Yojson.Safe.t
