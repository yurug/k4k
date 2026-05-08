(** [Toolchain_install] — probe-and-install for toolchain binaries the
    agent picks per project (ADR-012 §4-§7).

    Strict data-driven boundary: every per-tool fact lives in [mapping]
    below; the rest of the module is generic over [package_manager].
    Adding a tool is a one-line PR to [mapping], no logic change. *)

(** ADR-012 §4: user-scoped package managers k4k may invoke without
    sudo, plus [System] (sudo-only; surfaced to the user) and
    [Other_user_install] (generic curl-based user install). *)
type package_manager =
  | Opam              of string  (** opam package name *)
  | Pipx              of string  (** pipx app name *)
  | Uv_tool           of string  (** uv tool name *)
  | Cargo             of string  (** cargo crate name *)
  | Npm               of string  (** npm package name; HOME-scoped prefix *)
  | System            of string  (** system pkg name; sudo only *)
  | Other_user_install of string (** generic curl|sh install snippet *)

(** ADR-012 §4-§5: outcomes from [ensure]. The variants align with the
    operator-facing JSONL events emitted by the watcher daemon (batch 2). *)
type install_outcome =
  | Already_present of { binary : string; version : string }
  | Installed       of { binary : string; version : string; via : string }
  | Needs_user_consent of { binary : string;
                            reason : string;
                            suggested_command : string list option }
  | Failed          of string

(** ADR-012 §7: registry — binary name → package-manager.

    [@invariant P23 — every per-tool fact lives in this list; no module
                      outside this file may reference toolchain
                      binaries by name.] *)
val mapping : (string * package_manager) list

(** [ensure ~binary] is idempotent: if [binary] is already on [$PATH],
    returns [Already_present] without side-effects. Otherwise looks up
    [binary] in [mapping] and runs the appropriate user-scoped package
    manager via [Subprocess.run]; on success returns [Installed], on
    failure [Failed].

    For [System]-mapped binaries, no subprocess runs: the function
    returns [Needs_user_consent] with the suggested manual command.
    For [Opam]-mapped binaries with no [opam] on [$PATH], k4k attempts
    the user-scoped opam bootstrap (per ADR-012 §4); if that fails,
    returns [Needs_user_consent] with a manual-install hint.

    Test-only escape hatch: when the env var [K4K_TOOLCHAIN_INSTALL_STUB]
    is set, [ensure] consults a deterministic in-memory table seeded
    via [test_set_stub_outcome] instead of running subprocesses. The
    production harness leaves this unset; it exists to keep tests fast
    and hermetic. *)
val ensure : binary:string -> install_outcome

(** [@test_only] Seed a stub outcome for [binary]; subsequent
    [ensure ~binary] calls return this directly. Active only when
    [K4K_TOOLCHAIN_INSTALL_STUB] is set in the environment. *)
val test_set_stub_outcome : binary:string -> install_outcome -> unit

(** [@test_only] Clear all stub outcomes. *)
val test_reset_stubs : unit -> unit
