(** [Config] — per-project operator config at
    [.k4k/config.json].

    Auto-created at watcher startup if missing
    ([read_or_create]). The user edits it once to point at their
    chosen agent backend; the file is per-project (so different
    projects can use different agents).

    On-disk shape (JSON):
    {[
    {
      "_help": "<one-line operator hint>",
      "backend": { "command": "<argv-string>" | null }
    }
    ]}

    [backend.command] is a shell-style argv string parsed by
    [Backend_resolve.split_command]. Examples:
    - ["claude_code_backend"] (the bundled example, on $PATH after
      [dune install])
    - ["/path/to/ollama_backend --model qwen3.5:9b"]
    - [null] — disables the backend; the watcher logs
      [agent.unconfigured] and idles.

    The env var [K4K_BACKEND_COMMAND] (per
    [kb/runbooks/test-environment.md]) overrides the file when set
    — useful for one-off CI runs or test harnesses without
    mutating the project's config. *)

type t = {
  backend_command : string option;
}

(** [path ~k4k_dir] = [.k4k/config.json]. *)
val path : k4k_dir:string -> string

(** [read_or_create ~k4k_dir]:
    - If [config.json] exists, parse it (best-effort: a malformed
      file yields [{ backend_command = None }] without raising).
    - Otherwise [autodetect_backend_command ()] for a sensible
      default, write the file, and return the resulting record. *)
val read_or_create : k4k_dir:string -> t

(** [autodetect_backend_command ()] probes [$PATH] for the bundled
    reference backends in priority order:
    1. [claude_code_backend] — the most common operator default
       after [dune install].
    2. [ollama_backend] — the local-LLM alternative.
    Returns [Some name] when found, [None] otherwise. *)
val autodetect_backend_command : unit -> string option

(** [render_default ?backend ()] — pure: produces the JSON bytes
    [read_or_create] writes when bootstrapping a fresh project. *)
val render_default : ?backend:string option -> unit -> string
