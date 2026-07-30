#!/usr/bin/env bash
# When router UPnP cannot open ports, expose Rohomieo via outbound tunnels:
#   cloudflared  -> HTTPS/WSS web UI + signaling (*.trycloudflare.com)
#   bore         -> TCP TURN on bore.pub:<port>
#
# Writes: var/run/tunnels.env  (ROHOMIEO_PUBLIC_URL, ROHOMIEO_TURN_URL, PIDs)
# Prints the same on stdout as KEY=value lines for eval.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/var/run" "$ROOT/var/log" "$ROOT/var/tools"

ORIGIN="${1:-}"
if [[ -z "$ORIGIN" ]]; then
  echo "usage: $0 <https://lan-or-local:8443>" >&2
  exit 1
fi

CF="$("$ROOT/scripts/ensure-cloudflared.sh")"
BORE="$("$ROOT/scripts/ensure-bore.sh")"

# Stop prior tunnel helpers from earlier --global runs.
if [[ -f "$ROOT/var/run/tunnels.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT/var/run/tunnels.env" || true
  [[ -n "${CLOUDFLARED_PID:-}" ]] && kill "$CLOUDFLARED_PID" 2>/dev/null || true
  [[ -n "${BORE_PID:-}" ]] && kill "$BORE_PID" 2>/dev/null || true
  rm -f "$ROOT/var/run/tunnels.env"
fi

CF_LOG="$ROOT/var/log/cloudflared.log"
BORE_LOG="$ROOT/var/log/bore.log"
rm -f "$CF_LOG" "$BORE_LOG"

echo "==> UPnP unavailable — starting outbound tunnels (no router ports needed)" >&2

# cloudflared quick tunnel → origin (self-signed OK)
nohup "$CF" tunnel --no-autoupdate --url "$ORIGIN" --no-tls-verify \
  >"$CF_LOG" 2>&1 &
CF_PID=$!

# Wait for trycloudflare.com URL
PUBLIC_URL=""
for _ in $(seq 1 60); do
  if ! kill -0 "$CF_PID" 2>/dev/null; then
    echo "cloudflared exited early — see var/log/cloudflared.log" >&2
    tail -n 30 "$CF_LOG" >&2 || true
    exit 1
  fi
  PUBLIC_URL="$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$CF_LOG" 2>/dev/null | head -1 || true)"
  if [[ -n "$PUBLIC_URL" ]]; then
    break
  fi
  sleep 0.5
done
if [[ -z "$PUBLIC_URL" ]]; then
  echo "cloudflared did not print a trycloudflare.com URL — see var/log/cloudflared.log" >&2
  tail -n 40 "$CF_LOG" >&2 || true
  kill "$CF_PID" 2>/dev/null || true
  exit 1
fi
echo "==> web/signaling tunnel: $PUBLIC_URL" >&2

# bore TCP tunnel for TURN (:3478)
nohup "$BORE" local 3478 --to bore.pub >"$BORE_LOG" 2>&1 &
BORE_PID=$!

TURN_PORT=""
for _ in $(seq 1 40); do
  if ! kill -0 "$BORE_PID" 2>/dev/null; then
    echo "bore exited early — see var/log/bore.log" >&2
    cat "$BORE_LOG" >&2 || true
    kill "$CF_PID" 2>/dev/null || true
    exit 1
  fi
  # listening at bore.pub:XXXXX
  TURN_PORT="$(grep -oE 'bore\.pub:[0-9]+' "$BORE_LOG" 2>/dev/null | head -1 | cut -d: -f2 || true)"
  if [[ -n "$TURN_PORT" ]]; then
    break
  fi
  sleep 0.5
done
if [[ -z "$TURN_PORT" ]]; then
  echo "bore did not assign a public port — see var/log/bore.log" >&2
  cat "$BORE_LOG" >&2 || true
  kill "$CF_PID" "$BORE_PID" 2>/dev/null || true
  exit 1
fi
TURN_URL="turn:bore.pub:${TURN_PORT}"
echo "==> TURN TCP tunnel: $TURN_URL (WebRTC will use transport=tcp)" >&2

cat >"$ROOT/var/run/tunnels.env" <<EOF
ROHOMIEO_PUBLIC_URL=$PUBLIC_URL
ROHOMIEO_TURN_URL=$TURN_URL
ROHOMIEO_REACHABILITY=tunnel
CLOUDFLARED_PID=$CF_PID
BORE_PID=$BORE_PID
EOF

# Also emit for callers that `eval` / source
echo "ROHOMIEO_PUBLIC_URL=$PUBLIC_URL"
echo "ROHOMIEO_TURN_URL=$TURN_URL"
echo "ROHOMIEO_REACHABILITY=tunnel"
echo "CLOUDFLARED_PID=$CF_PID"
echo "BORE_PID=$BORE_PID"
