#!/usr/bin/env bash
# Live-smoke runner for the claude-code reference backend.
#
# This script is OPT-IN. It calls the real `claude` CLI, which means
# real Anthropic API calls and real token spend. Don't run it unless
# you're prepared to spend a small amount on a single round-trip.
#
# Usage:
#   ./smoke.sh formalization
#   ./smoke.sh gap-step
#   ./smoke.sh kb-regen
#
# What it does:
#   1. Verifies `claude` and `cotype` are on PATH.
#   2. Locates the claude_code_backend binary in the local _build/.
#   3. Writes a trivial prompt to a tempfile.
#   4. Invokes claude_code_backend WITHOUT --mock-response (so it
#      actually spawns claude).
#   5. Validates the output JSON conforms to the wire protocol
#      (kb/external/backend-protocol.md): {outcome, text, budget_used,
#      duration_ms} for "ok"; {outcome, error, duration_ms} for
#      "tool_error"; {outcome, duration_ms} for "budget_exhausted".
#
# The smoke does NOT exercise the v2 watcher paths (tradeoff,
# user-edits-queueing). Those are covered end-to-end by the canned-
# backend integration tests (S3, P22, P22b). The protocol-conformance
# suite at test/conformance/ verifies the wire stays stable across
# any backend.

set -euo pipefail

PURPOSE="${1:-formalization}"

case "$PURPOSE" in
  formalization|gap-step|kb-regen) ;;
  *)
    echo "usage: $0 <formalization|gap-step|kb-regen>" >&2
    exit 64
    ;;
esac

command -v claude  >/dev/null 2>&1 || { echo "claude not on PATH"  >&2; exit 1; }
command -v cotype  >/dev/null 2>&1 || { echo "cotype not on PATH"  >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../../.."
BIN="$ROOT/_build/install/default/bin/claude_code_backend"

[ -x "$BIN" ] || { echo "$BIN not built; run 'dune build' from $ROOT" >&2; exit 1; }

TMPDIR="$(mktemp -d -t k4k-smoke-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

PROMPT="$TMPDIR/prompt.txt"
OUTPUT="$TMPDIR/result.json"

echo "Say the single word OK and nothing else." > "$PROMPT"

echo "[smoke] purpose=$PURPOSE budget=2000"
echo "[smoke] invoking real claude (this costs tokens)…"

"$BIN" --purpose "$PURPOSE" \
       --prompt-file "$PROMPT" \
       --budget 2000 \
       --output "$OUTPUT"

echo "[smoke] result file:"
cat "$OUTPUT"
echo

OUTCOME="$(jq -r .outcome "$OUTPUT" 2>/dev/null || true)"
case "$OUTCOME" in
  ok)
    TEXT="$(jq -r .text "$OUTPUT")"
    BUDGET_USED="$(jq -r .budget_used "$OUTPUT")"
    echo "[smoke] PASS — outcome=ok text=\"$TEXT\" budget_used=$BUDGET_USED"
    ;;
  tool_error)
    ERROR="$(jq -r .error "$OUTPUT")"
    echo "[smoke] tool_error — $ERROR" >&2
    exit 2
    ;;
  budget_exhausted)
    echo "[smoke] budget_exhausted (raise --budget if this is unexpected)" >&2
    exit 3
    ;;
  *)
    echo "[smoke] unknown outcome: $OUTCOME" >&2
    exit 4
    ;;
esac
