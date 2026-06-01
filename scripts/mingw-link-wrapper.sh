#!/usr/bin/env bash
# Link wrapper: Rust gnu target wants libstdc++/gcc; llvm-mingw ships libc++.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLANG="${ROHOMIEO_LLVM_MINGW:-$ROOT/.tools/llvm-mingw}/bin/x86_64-w64-mingw32-clang++"
args=()
for a in "$@"; do
  case "$a" in
    -lstdc++) args+=("-lc++" "-lc++abi"); continue ;;
    -lgcc_eh) args+=("-lunwind"); continue ;;
    -lgcc) continue ;;
  esac
  args+=("$a")
done
exec "$CLANG" "${args[@]}"
