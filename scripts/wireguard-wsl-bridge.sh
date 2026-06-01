#!/usr/bin/env bash
# WSL2 WireGuard bridge — run VPN server inside WSL, expose via mirrored networking + Windows helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYDIR="$ROOT/infra/wireguard/keys"
TEMPLATE="$ROOT/infra/wireguard/wsl-bridge/server.conf.template"
WG_CONF="/etc/wireguard/wg0.conf"
LISTEN_PORT="${WG_LISTEN_PORT:-51820}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${CYAN}==>${NC} $*"; }
ok()    { echo -e "${GREEN}ok${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }
die()   { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

require_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null || die "This script is for WSL2 only"
}

require_wg() {
  command -v wg &>/dev/null || die "Install WireGuard: ./setup.sh --wsl"
  [[ -f "$KEYDIR/server.key" && -f "$KEYDIR/phone.pub" ]] || \
    die "Missing keys — run: ./scripts/wireguard-gen-keys.sh"
}

render_config() {
  local server_priv phone_pub
  server_priv=$(cat "$KEYDIR/server.key")
  phone_pub=$(cat "$KEYDIR/phone.pub")
  sed -e "s|@SERVER_PRIVATE_KEY@|$server_priv|g" \
      -e "s|@PHONE_PUBLIC_KEY@|$phone_pub|g" \
      "$TEMPLATE"
}

cmd_install() {
  require_wsl
  require_wg
  info "Writing $WG_CONF (sudo)..."
  render_config | sudo tee "$WG_CONF" >/dev/null
  sudo chmod 600 "$WG_CONF"
  ok "wg0.conf installed"
  info "Enable mirrored networking on Windows for UDP $LISTEN_PORT (best path):"
  echo "  powershell -File scripts\\windows\\wsl-enable-mirrored-network.ps1"
  echo "  then: wsl --shutdown  (from PowerShell), reopen WSL"
}

cmd_up() {
  require_wsl
  require_wg
  [[ -f "$WG_CONF" ]] || cmd_install
  if sudo wg show wg0 &>/dev/null; then
    warn "wg0 already up"
    cmd_status
    return 0
  fi
  info "Starting wg0 (sudo wg-quick up wg0)..."
  sudo wg-quick up wg0
  ok "WireGuard bridge up — server 10.8.0.1"
  cmd_status
  echo ""
  warn "Run on Windows (Admin PowerShell) to expose ports to your LAN:"
  echo "  powershell -File scripts\\windows\\wsl-bridge-portproxy.ps1"
  echo ""
  echo "Start Rohomieo signaling in WSL:"
  echo "  source .env.rohomieo && .local/bin/rohomieo-signaling"
  echo "Phone (on VPN): http://10.8.0.1:8443"
  echo "Host (Windows desktop): powershell -File scripts\\start-windows-host.ps1"
}

cmd_down() {
  require_wsl
  sudo wg-quick down wg0 2>/dev/null && ok "wg0 down" || warn "wg0 was not up"
}

cmd_status() {
  require_wsl
  echo ""
  if sudo wg show wg0 2>/dev/null; then
    echo ""
    ip -4 addr show wg0 2>/dev/null | grep -E 'inet |wg0' || true
    echo "WSL eth IP: $(hostname -I | awk '{print $1}')"
    if grep -qi microsoft /proc/version; then
      echo "Windows host (gateway): $(ip route show | awk '/default/ {print $3; exit}')"
    fi
  else
    warn "wg0 is not running — use: $0 up"
  fi
}

cmd_phone_config() {
  require_wg
  local server_pub phone_priv win_ip
  server_pub=$(cat "$KEYDIR/server.pub")
  phone_priv=$(cat "$KEYDIR/phone.key")
  read -r -p "Home public IP or DDNS [myhome.example.com]: " endpoint
  endpoint=${endpoint:-YOUR_PUBLIC_IP_OR_DDNS}
  cat <<EOF

# Import into WireGuard app on phone — save as rohomieo-phone.conf

[Interface]
PrivateKey = $phone_priv
Address = 10.8.0.30/32
DNS = 10.8.0.1

[Peer]
PublicKey = $server_pub
Endpoint = ${endpoint}:${LISTEN_PORT}
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25

EOF
}

usage() {
  cat <<EOF
Usage: $0 <command>

  install       Write /etc/wireguard/wg0.conf from infra/wireguard/keys/
  up            Start wg0 (VPN server 10.8.0.1 in WSL)
  down          Stop wg0
  status        Show wg0 state
  phone-config  Print phone peer config for clipboard import

See: infra/wireguard/wsl-bridge/README.md

EOF
}

case "${1:-}" in
  install)      cmd_install ;;
  up)           cmd_up ;;
  down)         cmd_down ;;
  status|st)    cmd_status ;;
  phone-config) cmd_phone_config ;;
  -h|--help|help|"") usage ;;
  *) die "Unknown command: $1" ;;
esac
