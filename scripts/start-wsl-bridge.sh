#!/usr/bin/env bash
# Start WSL WireGuard bridge + Rohomieo signaling (host still on Windows for desktop capture).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"

echo "════════════════════════════════════════════════════════"
echo " 1) WireGuard VPN server in WSL (10.8.0.1)"
echo " 2) Rohomieo signaling + web in WSL"
echo " 3) On Windows: rohomieo-host for screen capture"
echo "════════════════════════════════════════════════════════"

if ! sudo wg show wg0 &>/dev/null; then
  echo "Starting WireGuard bridge..."
  "$ROOT/scripts/wireguard-wsl-bridge.sh" up
else
  echo "wg0 already running"
fi

if [[ ! -x "$ROOT/target/release/rohomieo-signaling" ]]; then
  echo "Build signaling first: ./setup.sh --wsl" >&2
  exit 1
fi

echo ""
echo "Starting signaling on ${ROHOMIEO_BIND:-0.0.0.0:8443} ..."
echo "Phone on VPN: http://10.8.0.1:8443"
echo ""
echo "In Windows PowerShell (second machine / same PC):"
echo "  powershell -File scripts\\start-windows-host.ps1"
echo ""

exec "$ROOT/.local/bin/rohomieo-signaling"
