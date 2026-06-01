#!/usr/bin/env bash
# Build rohomieo-host.exe for Windows from WSL — MinGW/llvm-mingw only, no Visual Studio.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT="$ROOT"
cd "$ROOT"

# shellcheck source=lib/mingw-toolchain.sh
source "$ROOT/scripts/lib/mingw-toolchain.sh"
mingw_ensure

rustup target add x86_64-pc-windows-gnu >/dev/null 2>&1 || true

echo "==> Cross-building rohomieo-host.exe (MinGW, no MSVC)..."
cargo build --release --target x86_64-pc-windows-gnu -p rohomieo-host

src="$ROOT/target/x86_64-pc-windows-gnu/release/rohomieo-host.exe"
dst="$ROOT/target/release/rohomieo-host.exe"
mkdir -p "$(dirname "$dst")"
cp -f "$src" "$dst"
echo "ok $dst ($(file -b "$dst"))"
