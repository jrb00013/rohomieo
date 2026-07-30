#!/usr/bin/env bash
# Foreground signaling for scripts/run.sh (Ctrl+C tears down with the rest).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
_KEEP_MODE="${ROHOMIEO_MODE:-}"
# shellcheck disable=SC1091
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"
[[ -n "$_KEEP_MODE" ]] && ROHOMIEO_MODE="$_KEEP_MODE"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib-upnp.sh"

MODE="${ROHOMIEO_MODE:-local}"
BIND="${ROHOMIEO_BIND:-0.0.0.0:8443}"
PORT="${BIND##*:}"
WEB_ROOT="${ROHOMIEO_WEB_ROOT:-$ROOT/web/dist}"
CERT="${ROHOMIEO_CERT:-$ROOT/infra/certs/cert.pem}"
KEY="${ROHOMIEO_KEY:-$ROOT/infra/certs/key.pem}"

if [[ "$MODE" == "global" ]]; then
  trap 'upnp_close "$PORT" tcp' EXIT
  upnp_open "$PORT" tcp "signaling"
else
  echo "==> local mode — signaling on $BIND (no UPnP)"
fi

BIN="${ROHOMIEO_SIGNALING_BIN:-}"
if [[ -z "$BIN" ]]; then
  if [[ -x "$ROOT/target/release/rohomieo-signaling" ]]; then
    BIN="$ROOT/target/release/rohomieo-signaling"
  elif [[ -x "$ROOT/.local/bin/rohomieo-signaling" ]]; then
    BIN="$ROOT/.local/bin/rohomieo-signaling"
  elif command -v rohomieo-signaling >/dev/null 2>&1; then
    BIN="rohomieo-signaling"
  else
    BIN="$ROOT/target/debug/rohomieo-signaling"
  fi
fi
if [[ ! -x "$BIN" && "$BIN" != "rohomieo-signaling" ]]; then
  echo "==> building rohomieo-signaling (release)"
  (cd "$ROOT" && cargo build --release -p rohomieo-signaling)
  BIN="$ROOT/target/release/rohomieo-signaling"
fi

ARGS=(--bind "$BIND" --web-root "$WEB_ROOT")
[[ -f "$CERT" && -f "$KEY" ]] && ARGS+=(--cert "$CERT" --key "$KEY")
# Admin telemetry is off by default (safe for --global / public tunnels).
if [[ -n "${ROHOMIEO_ADMIN_TOKEN:-}" ]]; then
  ARGS+=(--admin-token "$ROHOMIEO_ADMIN_TOKEN")
elif [[ "$MODE" == "local" || "${ROHOMIEO_EXPOSE_ADMIN_API:-}" == "1" ]]; then
  ARGS+=(--expose-admin-api)
fi
exec "$BIN" "${ARGS[@]}"
