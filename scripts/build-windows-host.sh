#!/usr/bin/env bash
# Cross-build rohomieo-host.exe from WSL when MSVC is not installed on Windows.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
  echo "Installing mingw-w64 (sudo)..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-mingw-w64-x86-64
fi

rustup target add x86_64-pc-windows-gnu >/dev/null 2>&1 || true

echo "==> Cross-building rohomieo-host.exe (mingw)..."
cargo build --release --target x86_64-pc-windows-gnu -p rohomieo-host

src="$ROOT/target/x86_64-pc-windows-gnu/release/rohomieo-host.exe"
dst="$ROOT/target/release/rohomieo-host.exe"
cp -f "$src" "$dst"
echo "ok $dst"
ls -la "$dst"
