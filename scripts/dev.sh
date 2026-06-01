#!/usr/bin/env bash
# Start signaling (serves web/dist) + host on localhost for LAN testing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d web/dist ]]; then
  echo "Building web PWA..."
  (cd web && npm ci && npm run build)
fi

echo "Starting signaling on :8443..."
cargo run -p rohomieo-signaling -- --bind 127.0.0.1:8443 --web-root "$ROOT/web/dist" &
SIG_PID=$!
sleep 1

echo "Starting host..."
cargo run -p rohomieo-host -- --signaling ws://127.0.0.1:8443/ws &
HOST_PID=$!

trap 'kill $SIG_PID $HOST_PID 2>/dev/null' EXIT
echo "Open http://127.0.0.1:8443 — Ctrl+C to stop"
wait
