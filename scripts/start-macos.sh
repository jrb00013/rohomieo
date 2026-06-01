#!/usr/bin/env bash
# Start signaling + host on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"

for bin in rohomieo-signaling rohomieo-host; do
  if [[ ! -x "$ROOT/target/release/$bin" ]]; then
    echo "Missing $bin — run ./scripts/setup-macos.sh first" >&2
    exit 1
  fi
done

echo "Starting Rohomieo (macOS) — open http://127.0.0.1:8443"
echo "Ensure Screen Recording + Accessibility are granted for rohomieo-host"
"$ROOT/.local/bin/rohomieo-signaling" &
SIG=$!
sleep 1
"$ROOT/.local/bin/rohomieo-host" &
HOST=$!
trap 'kill $SIG $HOST 2>/dev/null' EXIT
wait
