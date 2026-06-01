#!/usr/bin/env bash
# Rohomieo unified setup — dispatches to platform scripts (complements setup-windows.ps1).
#
#   ./setup.sh              Auto-detect: wsl | macos | linux
#   ./setup.sh --linux      Native Linux (host + signaling)
#   ./setup.sh --wsl        WSL2 + Windows companion setup
#   ./setup.sh --macos      macOS (host + signaling)
#   ./setup.sh --windows    Print Windows-only instructions
#   ./setup.sh --all        WSL: Linux deps + Windows host setup
#
# Windows desktop capture always uses scripts/setup-windows.ps1 (PowerShell).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROHOMIEO_ROOT="$ROOT"

usage() {
  cat <<'EOF'
Rohomieo setup — pick a platform (shell scripts complement setup-windows.ps1):

  ./setup.sh              Auto-detect environment
  ./setup.sh --linux      Debian/Fedora/Arch native Linux
  ./setup.sh --wsl        WSL2 (signaling in WSL + Windows host via PowerShell)
  ./setup.sh --macos      macOS with Homebrew
  ./setup.sh --windows    Show Windows PowerShell setup steps only
  ./setup.sh --all        WSL full stack: setup-wsl.sh + setup-windows.ps1

Start after setup:
  ./scripts/start-linux.sh | start-wsl.sh | start-macos.sh
  powershell -File scripts\start-windows-host.ps1   (Windows)

EOF
}

detect() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi
      ;;
    MINGW*|MSYS*) echo windows ;;
    *) echo linux ;;
  esac
}

TARGET="${1:-auto}"
case "$TARGET" in
  auto) TARGET=$(detect) ;;
  -h|--help|help) usage; exit 0 ;;
  --linux|-l|linux) TARGET=linux ;;
  --wsl|-w|wsl) TARGET=wsl ;;
  --macos|-m|macos|osx|darwin) TARGET=macos ;;
  --windows|windows|win) TARGET=windows ;;
  --all|-a|all) TARGET=all ;;
  *) echo "Unknown option: $1"; usage; exit 1 ;;
esac

run() {
  local script="$ROOT/scripts/setup-$1.sh"
  if [[ ! -x "$script" ]]; then
    chmod +x "$script" "$ROOT"/scripts/lib/setup-common.sh 2>/dev/null || true
  fi
  bash "$script"
}

case "$TARGET" in
  linux)  run linux ;;
  wsl)    run wsl ;;
  macos)  run macos ;;
  all)
    export ROHOMIEO_SKIP_WINDOWS=0
    run wsl
    ;;
  windows)
    cat <<EOF

Run on Windows (PowerShell), not WSL:

  cd $ROOT   # or: cd \\\\wsl.localhost\\Ubuntu\\home\\YOU\\rohomieo
  powershell -ExecutionPolicy Bypass -File .\\scripts\\setup-windows.ps1

Requires: Visual Studio Build Tools (C++ workload) for link.exe

Then start:
  powershell -File .\\scripts\\start-windows-host.ps1

EOF
    ;;
esac
