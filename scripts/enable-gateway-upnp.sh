#!/usr/bin/env bash
# Flip UPnP on the LAN gateway via legitimate admin HTTPS (Copy-as-cURL).
# Credentials live in ~/.config/rohomieo/gateway.env (not in git).
#
# Usage:
#   ./scripts/enable-gateway-upnp.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${ROHOMIEO_GATEWAY_ENV:-$HOME/.config/rohomieo/gateway.env}"
EXAMPLE="$ROOT/scripts/gateway/gateway.env.example"

if [[ ! -f "$CFG" ]]; then
  mkdir -p "$(dirname "$CFG")"
  cp -n "$EXAMPLE" "$CFG"
  chmod 600 "$CFG"
  echo "==> created $CFG — set GATEWAY_PASS and GATEWAY_APPLY_CURL, then re-run"
  echo "    (DevTools → Network → Copy as cURL after enabling UPnP once)"
  exit 2
fi

exec python3 "$ROOT/scripts/gateway/enable-upnp-admin.py"
