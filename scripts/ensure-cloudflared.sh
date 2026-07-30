#!/usr/bin/env bash
# Download cloudflared into var/tools/ if missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/var/tools"
mkdir -p "$DIR"
BIN="$DIR/cloudflared"
if [[ -x "$BIN" ]]; then
  echo "$BIN"
  exit 0
fi
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) asset="cloudflared-linux-amd64" ;;
  aarch64|arm64) asset="cloudflared-linux-arm64" ;;
  *) echo "unsupported arch for cloudflared: $arch" >&2; exit 1 ;;
esac
url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
echo "==> downloading cloudflared ($asset)" >&2
curl -fsSL --location "$url" -o "$BIN"
chmod +x "$BIN"
echo "$BIN"
