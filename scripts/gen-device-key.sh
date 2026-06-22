#!/usr/bin/env bash
# Generate Ed25519 device keypair for future pairing (Phase 2).
# Stores in ~/.config/rohomieo/device.{pub,sec}
set -euo pipefail
DIR="${ROHOMIEO_CONFIG_DIR:-$HOME/.config/rohomieo}"
mkdir -p "$DIR"
PRIV="$DIR/device.sec"
PUB="$DIR/device.pub"

if [[ -f "$PRIV" ]]; then
  echo "Keys already exist:"
  echo "  $PRIV"
  echo "  $PUB"
  exit 0
fi

if command -v openssl >/dev/null; then
  openssl genpkey -algorithm ED25519 -out "$PRIV" 2>/dev/null
  openssl pkey -in "$PRIV" -pubout -out "$PUB" 2>/dev/null
  chmod 600 "$PRIV"
  echo "Generated Ed25519 keys (OpenSSL):"
  echo "  private: $PRIV"
  echo "  public:  $PUB"
  echo "Full host integration: see docs/ROADMAP.md Phase 2"
else
  echo "openssl not found — install openssl or wait for native Rust keygen in v0.3"
  exit 1
fi
