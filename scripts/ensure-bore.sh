#!/usr/bin/env bash
# Download bore into var/tools/ if missing (TCP tunnel for TURN when UPnP fails).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/var/tools"
mkdir -p "$DIR"
BIN="$DIR/bore"
if [[ -x "$BIN" ]]; then
  echo "$BIN"
  exit 0
fi
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) asset="bore-v0.6.0-x86_64-unknown-linux-musl.tar.gz" ;;
  aarch64|arm64) asset="bore-v0.6.0-aarch64-unknown-linux-musl.tar.gz" ;;
  *) echo "unsupported arch for bore: $arch" >&2; exit 1 ;;
esac
url="https://github.com/ekzhang/bore/releases/download/v0.6.0/${asset}"
echo "==> downloading bore ($asset)" >&2
tmp="$(mktemp -d)"
curl -fsSL --location "$url" -o "$tmp/bore.tgz"
tar -xzf "$tmp/bore.tgz" -C "$tmp"
# archive layout: bore binary at top level
find "$tmp" -type f -name bore -exec cp -f {} "$BIN" \;
chmod +x "$BIN"
rm -rf "$tmp"
echo "$BIN"
