#!/usr/bin/env bash
# Generate WireGuard keys under infra/wireguard/keys/ (does not install configs).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYDIR="$ROOT/infra/wireguard/keys"
umask 077
mkdir -p "$KEYDIR"

if ! command -v wg &>/dev/null; then
  echo "wg not found — run ./setup.sh first to install WireGuard tools" >&2
  exit 1
fi

gen() {
  local name="$1"
  if [[ -f "$KEYDIR/${name}.key" ]]; then
    echo "exists: $KEYDIR/${name}.key"
    return
  fi
  wg genkey | tee "$KEYDIR/${name}.key" | wg pubkey >"$KEYDIR/${name}.pub"
  chmod 600 "$KEYDIR/${name}.key"
  echo "created: $KEYDIR/${name}.key + .pub"
}

gen server
gen laptop
gen phone

echo ""
echo "Next: edit infra/wireguard/*.conf.example with these keys — see infra/wireguard/README.md"
