(** [Backend_canned] — load a sequence of canned agent responses from
    a JSON file (test-only, via [K4K_STUB_RESPONSES]).

    File format: a JSON array of [{"purpose": "Gap_step" | "Formalization"
    | "Kb_regen", "text": "..."}] objects. Per-purpose queues are
    consumed in document order; once a queue is empty further invokes
    of that purpose return [`Tool_error]. Used by the v2 integration
    test to drive [Version_loop] without a real LLM. *)

type t

(** [load_from_path p] reads + parses [p]; entries with unknown
    purposes / missing text are silently dropped. *)
val load_from_path : string -> (t, string) result

(** [invoke t ~purpose ~prompt ~budget] — pops the next entry whose
    purpose matches; returns [`Tool_error] when the queue is empty. *)
val invoke :
  t ->
  purpose:Agent_backend.purpose ->
  prompt:string ->
  budget:int ->
  Agent_backend.result
