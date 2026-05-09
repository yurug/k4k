(** [Backend_resolve] — pick the agent-invoke closure for a watcher
    run.

    Resolution order:
    1. [K4K_STUB_RESPONSES] — test-only canned backend.
    2. [K4K_BACKEND_COMMAND] — env override (one-off / CI without
       mutating the project's config).
    3. [.k4k/config.json] [backend.command] — the per-project
       operator config, auto-created at first run by [Config]
       (autodetects [claude_code_backend] / [ollama_backend] on
       [$PATH] when seeding the file).
    4. None of the above → emit [agent.unconfigured] and return a
       closure that yields [Tool_error] on every call so the
       watcher degrades gracefully (logs [version.skip] and keeps
       polling instead of spinning on a half-configured project).

    Allocated ONCE per watcher run; reuse the closure across every
    [try_run_version] iteration so the canned backend's per-purpose
    queues persist. *)

type emit_fn = string -> Yojson.Safe.t -> unit

(** [split_command s] — parse a shell-style command string into argv.
    Handles double-quoted segments and backslash escapes inside
    them; no [$VAR] / [~] expansion. Empty / whitespace-only input
    yields []. *)
val split_command : string -> string list

(** [resolve ~emit ~k4k_dir] returns the agent-invoke closure per
    the resolution order in this module's header. The closure is
    shared across the watcher's full lifetime. [k4k_dir] is the
    project's [.k4k/] path; [Config.read_or_create ~k4k_dir]
    bootstraps it on first run. *)
val resolve :
  emit:emit_fn ->
  k4k_dir:string ->
  Version_loop.agent_invoke
