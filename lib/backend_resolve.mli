(** [Backend_resolve] — pick the agent-invoke closure for a watcher
    run from the environment.

    Resolution order (audit-2026-05-08-axis6 H-3):
    1. [K4K_STUB_RESPONSES] — test-only canned backend.
    2. [K4K_BACKEND_COMMAND] — production: shell-style command
       string for an executable conforming to
       [kb/external/backend-protocol.md] (ADR-009 / ADR-012).
    3. Neither set → emit [agent.unconfigured] and return a closure
       that yields [Tool_error] on every call so the watcher
       degrades gracefully (logs [version.skip] and keeps polling
       instead of spinning on a half-configured project).

    Allocated ONCE per watcher run; reuse the closure across every
    [try_run_version] iteration so the canned backend's per-purpose
    queues persist. *)

type emit_fn = string -> Yojson.Safe.t -> unit

(** [split_command s] — parse a shell-style command string into argv.
    Handles double-quoted segments and backslash escapes inside
    them; no [$VAR] / [~] expansion. Empty / whitespace-only input
    yields []. *)
val split_command : string -> string list

(** [resolve ~emit] returns the agent-invoke closure per the
    resolution order in this module's header. The closure is shared
    across the watcher's full lifetime. *)
val resolve : emit:emit_fn -> Version_loop.agent_invoke
