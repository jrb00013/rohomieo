#!/usr/bin/env bash
# Download bore into var/tools/ if missing (version-pinned + SHA-256 verified).
# Used as a TCP TURN tunnel when router UPnP is unavailable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/var/tools"
mkdir -p "$DIR"
BIN="$DIR/bore"

BORE_VERSION="0.6.0"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)
    asset="bore-v${BORE_VERSION}-x86_64-unknown-linux-musl.tar.gz"
    want_archive="e484d1e3acba77169b773f31a5bfb34192d4b660f44a094a658a2522cd2270f7"
    want_bin="60548b7a145ba334981b19fda7cd0210d24a108a3d0dc113919b33fd2eaa90ab"
    ;;
  aarch64|arm64)
    asset="bore-v${BORE_VERSION}-aarch64-unknown-linux-musl.tar.gz"
    want_archive="ffc4515f3617420b243758cf36ed6a63208d7dba76b2ec3e90d1f476a9742951"
    want_bin="348068ca74769635b91e9243d6a2befda516b74a7c692f14263513e9c675706a"
    ;;
  *) echo "unsupported arch for bore: $arch" >&2; exit 1 ;;
esac

if [[ -x "$BIN" ]]; then
  have="$(sha256sum "$BIN" | awk '{print $1}')"
  if [[ "$have" == "$want_bin" ]]; then
    echo "$BIN"
    exit 0
  fi
  echo "==> bore checksum mismatch — re-downloading pinned v${BORE_VERSION}" >&2
  rm -f "$BIN"
fi

url="https://github.com/ekzhang/bore/releases/download/v${BORE_VERSION}/${asset}"
echo "==> downloading bore v${BORE_VERSION} ($asset)" >&2
tmp="$(mktemp -d)"
curl -fsSL --location "$url" -o "$tmp/bore.tgz"
got_archive="$(sha256sum "$tmp/bore.tgz" | awk '{print $1}')"
if [[ "$got_archive" != "$want_archive" ]]; then
  rm -rf "$tmp"
  echo "bore archive checksum failed (got $got_archive want $want_archive)" >&2
  exit 1
fi
tar -xzf "$tmp/bore.tgz" -C "$tmp"
find "$tmp" -type f -name bore -exec cp -f {} "$BIN" \;
chmod +x "$BIN"
got_bin="$(sha256sum "$BIN" | awk '{print $1}')"
rm -rf "$tmp"
if [[ "$got_bin" != "$want_bin" ]]; then
  rm -f "$BIN"
  echo "bore binary checksum failed (got $got_bin want $want_bin)" >&2
  exit 1
fi
echo "$BIN"
