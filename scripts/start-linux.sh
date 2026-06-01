#!/usr/bin/env bash
# Start signaling + host on native Linux.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"

for bin in rohomieo-signaling rohomieo-host; do
  if [[ ! -x "$ROOT/target/release/$bin" ]]; then
    echo "Missing $bin — run ./scripts/setup-linux.sh first" >&2
    exit 1
  fi
done

export DISPLAY="${DISPLAY:-:0}"
echo "Starting Rohomieo (Linux) — open http://127.0.0.1:8443"
"$ROOT/.local/bin/rohomieo-signaling" &
SIG=$!
sleep 1
"$ROOT/.local/bin/rohomieo-host" &
HOST=$!
trap 'kill $SIG $HOST 2>/dev/null' EXIT
wait
