#!/bin/sh
# Synthetic verifier conforming to kb/external/verifier-protocol.md.
# Deterministic stub: emits a wire-protocol-conformant JSON result for
# the focus list. Property IDs listed in $K4K_SYNTH_ESTABLISHED (space-
# separated) get status "established"; all other focus ids get
# "unknown". Used only by v2 conformance tests.
set -e
workdir=""; output=""; focus=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) workdir="$2"; shift 2 ;;
    --focus)
      shift
      while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do
        focus="$focus $1"; shift
      done ;;
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$output" ] && [ -n "$workdir" ] || { echo "missing --output/--workdir" >&2; exit 64; }
items=""; sep=""
for id in $focus; do
  status="unknown"
  for est in ${K4K_SYNTH_ESTABLISHED:-}; do
    [ "$id" = "$est" ] && status="established"
  done
  items="$items$sep\"$id\":\"$status\""; sep=","
done
cat > "$output" <<EOF
{"by_property":{$items},"raw_exit_code":0,"duration_ms":0,"warnings":[]}
EOF
