#!/usr/bin/env bash
# Build Windows .exe binaries from WSL — llvm-mingw only, no Visual Studio.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT="$ROOT"
cd "$ROOT"

# shellcheck source=lib/mingw-toolchain.sh
source "$ROOT/scripts/lib/mingw-toolchain.sh"
mingw_ensure

rustup target add x86_64-pc-windows-gnu >/dev/null 2>&1 || true

echo "==> Cross-building rohomieo-signaling + rohomieo-host (MinGW)..."
cargo build --release --target x86_64-pc-windows-gnu -p rohomieo-signaling -p rohomieo-host

for bin in rohomieo-signaling rohomieo-host; do
  src="$ROOT/target/x86_64-pc-windows-gnu/release/${bin}.exe"
  dst="$ROOT/target/release/${bin}.exe"
  mkdir -p "$(dirname "$dst")"
  cp -f "$src" "$dst"
  echo "ok $dst ($(file -b "$dst"))"
done

# shellcheck source=lib/bundle-windows-runtime.sh
source "$ROOT/scripts/lib/bundle-windows-runtime.sh"
