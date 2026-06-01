#!/usr/bin/env bash
# Copy llvm-mingw runtime DLLs next to .exe so Windows does not show "code execution cannot proceed".
set -euo pipefail
ROOT="${ROHOMIEO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="$ROOT/target/release"
MINGW_BIN="${ROOT}/.tools/llvm-mingw/x86_64-w64-mingw32/bin"

[[ -d "$MINGW_BIN" ]] || { echo "llvm-mingw not found — run ./scripts/build-windows-host.sh first"; exit 1; }

mkdir -p "$OUT"
for dll in libunwind.dll libc++.dll libwinpthread-1.dll; do
  if [[ -f "$MINGW_BIN/$dll" ]]; then
    cp -f "$MINGW_BIN/$dll" "$OUT/"
    echo "ok $OUT/$dll"
  fi
done
