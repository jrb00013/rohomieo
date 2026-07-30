#!/usr/bin/env bash
# Download cloudflared into var/tools/ if missing (version-pinned + SHA-256 verified).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/var/tools"
mkdir -p "$DIR"
BIN="$DIR/cloudflared"

# Pin a known release — do not follow /latest (supply-chain).
CF_VERSION="2026.7.3"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)
    asset="cloudflared-linux-amd64"
    want_sha="9d71c677db00134c1bd4144b7783486b654ad281b1ea62b4972098d19f770f17"
    ;;
  aarch64|arm64)
    asset="cloudflared-linux-arm64"
    want_sha="65259e652a7bea08bf5df603233ab22b8bf3116af8df9f9206209af6a1b955c0"
    ;;
  *) echo "unsupported arch for cloudflared: $arch" >&2; exit 1 ;;
esac

if [[ -x "$BIN" ]]; then
  have="$(sha256sum "$BIN" | awk '{print $1}')"
  if [[ "$have" == "$want_sha" ]]; then
    echo "$BIN"
    exit 0
  fi
  echo "==> cloudflared checksum mismatch — re-downloading pinned ${CF_VERSION}" >&2
  rm -f "$BIN"
fi

url="https://github.com/cloudflare/cloudflared/releases/download/${CF_VERSION}/${asset}"
echo "==> downloading cloudflared ${CF_VERSION} ($asset)" >&2
tmp="$(mktemp)"
curl -fsSL --location "$url" -o "$tmp"
got="$(sha256sum "$tmp" | awk '{print $1}')"
if [[ "$got" != "$want_sha" ]]; then
  rm -f "$tmp"
  echo "cloudflared checksum failed (got $got want $want_sha)" >&2
  exit 1
fi
mv -f "$tmp" "$BIN"
chmod +x "$BIN"
echo "$BIN"
