#!/usr/bin/env bash
# Local coturn TURN relay so phones behind symmetric NAT / CGNAT can still
# reach the host — STUN alone often cannot. Auto-generates credentials into
# .env.rohomieo on first run.
#
# Only used for --global sessions (run.sh skips this in --local mode).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env.rohomieo"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib-upnp.sh"

_KEEP_MODE="${ROHOMIEO_MODE:-}"
_KEEP_PUBLIC_IP="${ROHOMIEO_PUBLIC_IP:-}"
_KEEP_TURN_URL="${ROHOMIEO_TURN_URL:-}"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
[[ -n "$_KEEP_MODE" ]] && ROHOMIEO_MODE="$_KEEP_MODE"
[[ -n "$_KEEP_PUBLIC_IP" ]] && ROHOMIEO_PUBLIC_IP="$_KEEP_PUBLIC_IP"
[[ -n "$_KEEP_TURN_URL" ]] && ROHOMIEO_TURN_URL="$_KEEP_TURN_URL"

MODE="${ROHOMIEO_MODE:-global}"
if [[ "$MODE" != "global" ]]; then
  echo "==> local mode — skipping TURN relay"
  exit 0
fi

if ! command -v turnserver >/dev/null; then
  echo "coturn not installed — attempting install"
  # shellcheck disable=SC1091
  source "$ROOT/scripts/lib-platform.sh"
  PLATFORM="$(rohomieo_detect_platform)"
  if command -v apt-get >/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq coturn
  elif [[ "$PLATFORM" == "macos" ]]; then
    BREW="$(rohomieo_brew_bin || true)"
    if [[ -n "$BREW" ]]; then
      "$BREW" install coturn
      export PATH="$(rohomieo_tool_path "${HOME:-}"):${PATH:-}"
    else
      echo "Install Homebrew (https://brew.sh) then: brew install coturn" >&2
      exit 1
    fi
  else
    echo "Install coturn manually: https://github.com/coturn/coturn" >&2
    exit 1
  fi
  if ! command -v turnserver >/dev/null; then
    echo "coturn install finished but turnserver is still not on PATH" >&2
    exit 1
  fi
fi

# Package install may enable a system coturn on :3478 — stop it so our
# session-scoped config (external-ip + generated creds) can bind the port.
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet coturn 2>/dev/null; then
    echo "==> stopping system coturn service (using session config instead)"
    sudo systemctl stop coturn || true
  fi
fi

if [[ -z "${ROHOMIEO_TURN_USER:-}" || -z "${ROHOMIEO_TURN_PASS:-}" ]]; then
  ROHOMIEO_TURN_USER="rh$(head -c 6 /dev/urandom | xxd -p)"
  ROHOMIEO_TURN_PASS="$(head -c 24 /dev/urandom | xxd -p)"
  export ROHOMIEO_TURN_USER ROHOMIEO_TURN_PASS
  echo "==> generated session-scoped TURN credentials (not saved to disk)"
fi

PUBLIC_IP="${ROHOMIEO_PUBLIC_IP:-$(curl -fsS --max-time 3 ifconfig.me || true)}"
# Tunnel mode may have no routable public IP; coturn still needs external-ip for candidates.
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="$(upnp_local_ip)"
fi
if [[ -z "$PUBLIC_IP" ]]; then
  echo "TURN needs ROHOMIEO_PUBLIC_IP or a detectable LAN IP" >&2
  exit 1
fi
ROHOMIEO_TURN_URL="${ROHOMIEO_TURN_URL:-turn:$PUBLIC_IP:3478}"

# Fail fast if something else already owns :3478 (e.g. another couchlink/rohomieo session).
if ss -ulnp 2>/dev/null | grep -q ':3478'; then
  echo "UDP :3478 is already in use — stop the other TURN/coturn session and retry." >&2
  ss -ulnp 2>/dev/null | grep ':3478' | head -3 >&2 || true
  exit 1
fi

RUNTIME_CONF="$(mktemp /tmp/rohomieo-turnserver.XXXXXX.conf)"
trap 'rm -f "$RUNTIME_CONF"; upnp_close 3478 udp; upnp_close 3478 tcp' EXIT
sed \
  -e "s/ROHOMIEO_TURN_USER/$ROHOMIEO_TURN_USER/" \
  -e "s/ROHOMIEO_TURN_PASS/$ROHOMIEO_TURN_PASS/" \
  "$ROOT/infra/turn/turnserver.conf.example" > "$RUNTIME_CONF"
echo "external-ip=$PUBLIC_IP" >> "$RUNTIME_CONF"
# Avoid needing root for /var/run/turnserver.pid
echo "pidfile=/tmp/rohomieo-turnserver.pid" >> "$RUNTIME_CONF"
# Quiet noisy discovery across every docker/WSL bridge NIC
echo "listening-ip=0.0.0.0" >> "$RUNTIME_CONF"
_RELAY_IP="$(upnp_local_ip)"
[[ -n "$_RELAY_IP" ]] && echo "relay-ip=$_RELAY_IP" >> "$RUNTIME_CONF"

upnp_open 3478 udp "turn"
upnp_open 3478 tcp "turn"

echo "==> starting local TURN relay on :3478 (user=$ROHOMIEO_TURN_USER external-ip=$PUBLIC_IP)"
turnserver -c "$RUNTIME_CONF"
