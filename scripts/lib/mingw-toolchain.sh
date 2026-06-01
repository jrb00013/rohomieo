#!/usr/bin/env bash
# Portable MinGW for Windows cross-build from WSL — no Visual Studio.
set -euo pipefail

mingw_apply_scrap_patch() {
  local patch="${ROHOMIEO_ROOT:?}/scripts/patches/scrap-build.rs"
  local build_rs
  while IFS= read -r build_rs; do
    if ! cmp -s "$patch" "$build_rs" 2>/dev/null; then
      cp "$patch" "$build_rs"
      echo "ok patched $build_rs"
    fi
  done < <(find "${CARGO_HOME:-$HOME/.cargo}/registry/src" -path '*/scrap-0.5.0/build.rs' 2>/dev/null)
  # Host-side build-script cache must be cleared or scrap stays on x11.
  rm -rf "${ROHOMIEO_ROOT}/target/release/build/scrap-"* \
         "${ROHOMIEO_ROOT}/target/release/.fingerprint/scrap-"* 2>/dev/null || true
}

mingw_ensure_llvm_mingw() {
  local ver="${ROHOMIEO_LLVM_MINGW_VER:-20260519}"
  local cache="${ROHOMIEO_ROOT}/.tools/llvm-mingw"
  local bin="$cache/bin"
  if [[ -x "$bin/x86_64-w64-mingw32-clang" ]]; then
    export PATH="$bin:$PATH"
    export CC_x86_64_pc_windows_gnu="$bin/x86_64-w64-mingw32-clang"
    export CXX_x86_64_pc_windows_gnu="$bin/x86_64-w64-mingw32-clang++"
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="$bin/x86_64-w64-mingw32-clang"
    return 0
  fi
  echo "==> Downloading llvm-mingw (no VS, ~60MB)..."
  mkdir -p "${ROHOMIEO_ROOT}/.tools"
  local url="https://github.com/mstorsjo/llvm-mingw/releases/download/${ver}/llvm-mingw-${ver}-ucrt-ubuntu-22.04-x86_64.tar.xz"
  local tmp extracted="llvm-mingw-${ver}-ucrt-ubuntu-22.04-x86_64"
  tmp=$(mktemp -d)
  curl -fsSL "$url" -o "$tmp/llvm-mingw.tar.xz"
  tar -xJf "$tmp/llvm-mingw.tar.xz" -C "${ROHOMIEO_ROOT}/.tools"
  rm -rf "$cache"
  mv "${ROHOMIEO_ROOT}/.tools/$extracted" "$cache"
  rm -rf "$tmp"
  echo "ok llvm-mingw at $cache"
}

mingw_ensure_system() {
  if command -v x86_64-w64-mingw32-g++ &>/dev/null; then
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-g++
    return 0
  fi
  if command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc
    return 0
  fi
  if command -v x86_64-w64-mingw32-clang &>/dev/null; then
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-clang
    return 0
  fi
  return 1
}

mingw_ensure() {
  # Prefer llvm-mingw (bundled under .tools); avoid broken/partial system mingw.
  if [[ -x "${ROHOMIEO_ROOT}/.tools/llvm-mingw/bin/x86_64-w64-mingw32-clang" ]]; then
    :
  else
    mingw_ensure_llvm_mingw
  fi
  local bin="${ROHOMIEO_ROOT}/.tools/llvm-mingw/bin"
  local mingw_lib="${ROHOMIEO_ROOT}/.tools/llvm-mingw/x86_64-w64-mingw32/lib"
  export PATH="$bin:$PATH"
  export CC_x86_64_pc_windows_gnu="$bin/x86_64-w64-mingw32-clang"
  export CXX_x86_64_pc_windows_gnu="$bin/x86_64-w64-mingw32-clang++"
  export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="$ROHOMIEO_ROOT/scripts/mingw-link-wrapper.sh"
  chmod +x "$ROHOMIEO_ROOT/scripts/mingw-link-wrapper.sh" 2>/dev/null || true
  export RUSTFLAGS="${RUSTFLAGS:-} -L native=$mingw_lib"
  mingw_apply_scrap_patch
}
