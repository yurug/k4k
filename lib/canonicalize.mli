(** [Canonicalize] — pure canonicalization of [Characterization.t].

    This module is responsible for the determinism boundary defined in
    ADR-005. It implements P4 (determinism on canonical AST) and is
    purely functional: no I/O, no [Sys.getenv], no [Unix.time].

    Key design decisions: sort set-like arrays by a deterministic key,
    squeeze whitespace inside free-form strings, never rename
    user-provided identifiers; emit canonical JSON (object keys
    lex-sorted, no whitespace, ASCII-escaped) and SHA-256 it into the
    [hash] field. *)

(** [canonicalize c] returns a canonical form of [c]:
    - set-like arrays sorted by a deterministic key
      ([argv] by name, [errors] by id, [fs_contract.reads/writes/creates] by
      glob, [examples_accept/refuse] by name, [exit_codes] by code);
    - free-form strings stripped + run-of-whitespace squeezed to a
      single space;
    - the [hash] field set to the lower-case hex SHA-256 of the
      canonical-JSON serialization with the [hash] field omitted.

    @invariant P4 — idempotent: [canonicalize (canonicalize x) = canonicalize x].
    @invariant P4 — structurally-equivalent inputs produce equal hashes. *)
val canonicalize : Characterization.t -> Characterization.t

(** [canonical_bytes c] returns the canonical-JSON byte string used to
    compute [c.hash], i.e. the JSON serialization with [hash] zeroed.
    Useful for divergence reports and audits. *)
val canonical_bytes : Characterization.t -> string

(** [equal a b] iff [a.hash] equals [b.hash]. Both inputs must already be
    canonicalized; otherwise the comparison is meaningless.

    @invariant P4 — the only equality test on characterizations. *)
val equal : Characterization.t -> Characterization.t -> bool

(** [canonical_json_string v] — internal canonical-JSON printer, exposed
    so [Persist] can produce the canonical bytes on disk for
    [desired/spec.json].

    Canonical JSON: object keys lex-sorted, no whitespace between
    tokens, every code point ≥ 0x7f escaped as [\uXXXX]. *)
val canonical_json_string : Yojson.Safe.t -> string
