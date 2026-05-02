(** [Stability] — structural + semantic stability of an interaction
    file.

    This module is responsible for the binary stable/unstable verdict
    (P3) and, in step 2, for the two-run formalization protocol per
    [kb/spec/algorithms.md#formalization].

    Structural rules: every required user-section present, non-empty.
    Semantic rules: two independent agent calls produce
    canonically-equal ASTs (P18); a stable result is cached by user-
    section hash (P19). *)

(** A binary stability verdict. *)
type t =
  | Stable
  | Unstable of Error.issue list

(** [check_structural file] — first stage. *)
val check_structural : Parser.interaction_file -> t

(** [check_semantic file] — legacy step-1 stub (always [Stable]).
    Step 2's real check lives in [semantic_check_with_backend]. *)
val check_semantic : Parser.interaction_file -> t

(** [is_stable t]. *)
val is_stable : t -> bool

(** [user_section_hashes file] — keyed map of user-section id to
    sha256 of the section's body. The whole map is the cache key for P19. *)
val user_section_hashes :
  Parser.interaction_file -> (string * string) list

(** [render_user_sections file] — flat-text concatenation of every
    user-owned section's [id + body], used as the [{{user_sections}}]
    placeholder substitution in [prompts/formalize.md]. *)
val render_user_sections : Parser.interaction_file -> string

(** Outcome of the two-run protocol. *)
type semantic_outcome =
  | Sem_cached  of Characterization.t                       (** P19 hit. *)
  | Sem_stable  of Characterization.t * string list         (** Equal hashes. *)
  | Sem_unstable of Error.issue list * string list          (** Diverged or invalid. *)

(** A type-erased agent-backend invoker. The harness builds one of
    these by closing over the chosen backend module + value. *)
type 'b backend_invoker = {
  invoke :
    purpose:Agent_backend.purpose ->
    prompt:string ->
    budget:int ->
    Agent_backend.result;
  bk : 'b;
}

(** [semantic_check_with_backend ~k4k_dir ~prompt ~budget ~prev_hashes
    ~current_hashes ~cached_desired inv] — runs the formalization
    protocol per [algorithms.md#formalization]:

    - if [prev_hashes = current_hashes] and [cached_desired = Some _],
      return [Sem_cached] without calling the backend (P19 hit);
    - otherwise call the backend twice with [prompt] and [budget]; parse
      both responses with [Permissive_json] then strict-validate via
      [Characterization_decoder]; canonicalize; compare hashes.

    @raise Error.K4k_error E_budget on budget exhaustion at either call.
    @invariant P18 — the protocol always runs at least two calls when
                     the cache misses.
    @invariant P19 — the cache short-circuit suppresses both calls. *)
val semantic_check_with_backend :
  k4k_dir:string ->
  prompt:string ->
  budget:int ->
  prev_hashes:(string * string) list ->
  current_hashes:(string * string) list ->
  cached_desired:Characterization.t option ->
  'b backend_invoker ->
  semantic_outcome
