#!/usr/bin/env bash
# Record versions of every external dep documented in kb/external/*.md.
# Used by the weekly drift-watch runbook (kb/runbooks/drift-watch.md).
#
# Output is machine-friendly: one line per tool, "<tool>: <version>" or
# "<tool>: not-installed". Stable across re-runs, suitable for diff'ing.

set -u

probe() {
  local tool="$1" cmd="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    local v
    v=$($cmd 2>/dev/null | head -1 | tr -d '\r')
    printf '%s: %s\n' "$tool" "${v:-unknown}"
  else
    printf '%s: not-installed\n' "$tool"
  fi
}

printf '# Dep versions — recorded %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Hardcoded runtime deps (lib/ shells out to these).
probe cotype "cotype --version"
probe git    "git --version"

# Reference example dependencies (examples/ binaries shell out to these).
probe dune   "dune --version"
probe ocaml  "ocaml --version"
probe curl   "curl --version"
probe diff3  "diff3 --version"

# Optional: live-mode backends.
probe claude "claude --version"
probe ollama "ollama --version"
