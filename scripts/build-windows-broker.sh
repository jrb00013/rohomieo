#!/usr/bin/env bash
# Cross-build RohomieoBroker + ctl (MinGW) into target/release/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT="$ROOT"
# shellcheck source=lib/mingw-toolchain.sh
source "$ROOT/scripts/lib/mingw-toolchain.sh"
mingw_ensure

CXX=""
if command -v x86_64-w64-mingw32-clang++ &>/dev/null; then
  CXX=x86_64-w64-mingw32-clang++
elif command -v x86_64-w64-mingw32-g++ &>/dev/null; then
  CXX=x86_64-w64-mingw32-g++
else
  echo "No MinGW C++ cross-compiler found" >&2
  exit 1
fi

echo "==> Building RohomieoBroker with $CXX"
make -C "$ROOT/native/rohomieo-broker" CXX="$CXX"
echo "ok $ROOT/target/release/rohomieo-broker.exe"
echo "ok $ROOT/target/release/rohomieo-broker-ctl.exe"
