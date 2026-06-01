#!/usr/bin/env bash
# Rohomieo unified setup — dispatches to platform scripts (complements setup-windows.ps1).
#
#   ./setup.sh              Auto-detect + install
#   ./setup.sh --wsl        WSL2 install
#   ./setup.sh --start      Start services (bridge + signaling + Windows host)
#   ./setup.sh --wsl --start   Install then start
#   ./setup.sh --stop       Stop background services + wg0
#
# WireGuard: ROHOMIEO_SKIP_WIREGUARD=1  |  Windows GUI: ROHOMIEO_WG_WINDOWS_GUI=1
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROHOMIEO_ROOT="$ROOT"

# shellcheck source=scripts/lib/setup-common.sh
source "$ROOT/scripts/lib/setup-common.sh"
# shellcheck source=scripts/lib/setup-start.sh
source "$ROOT/scripts/lib/setup-start.sh"

RUN_SETUP=false
RUN_START=false
RUN_STOP=false
RUN_FOREGROUND=false
TARGET="auto"

usage() {
  cat <<'EOF'
Rohomieo setup

  ./setup.sh                 Install (auto-detect platform)
  ./setup.sh --wsl           Install for WSL2
  ./setup.sh --linux         Install for native Linux
  ./setup.sh --macos         Install for macOS

  ./setup.sh --start         Start WireGuard bridge + services (no install)
  ./setup.sh --wsl --start   Install then start
  ./setup.sh --stop          Stop signaling/host + bring down wg0

  ./setup.sh --start --foreground   WSL: run signaling in foreground (Ctrl+C)

  ./setup.sh --windows       Windows PowerShell setup instructions
  ./setup.sh --all           WSL install + Windows companion build

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help) usage; exit 0 ;;
    --start)        RUN_START=true; shift ;;
    --stop)         RUN_STOP=true; shift ;;
    --foreground|-f) RUN_FOREGROUND=true; shift ;;
    --linux|-l|linux) TARGET=linux; RUN_SETUP=true; shift ;;
    --wsl|-w|wsl)     TARGET=wsl; RUN_SETUP=true; shift ;;
    --macos|-m|macos) TARGET=macos; RUN_SETUP=true; shift ;;
    --windows|win)  TARGET=windows; shift ;;
    --all|-a|all)   TARGET=all; RUN_SETUP=true; shift ;;
    auto) shift ;;
    *)
      if [[ "$TARGET" == "auto" && "$RUN_SETUP" == "false" && "$RUN_START" == "false" && "$RUN_STOP" == "false" ]]; then
        TARGET=$(detect)
        RUN_SETUP=true
      else
        echo "Unknown option: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

# Default: install only when no action flags
if [[ "$RUN_SETUP" == "false" && "$RUN_START" == "false" && "$RUN_STOP" == "false" ]]; then
  TARGET=$(detect)
  RUN_SETUP=true
fi

resolve_target() {
  [[ "$TARGET" == "auto" ]] && TARGET=$(detect)
}

resolve_target

run_setup() {
  local script="$ROOT/scripts/setup-$1.sh"
  chmod +x "$script" "$ROOT"/scripts/lib/*.sh "$ROOT"/scripts/*.sh 2>/dev/null || true
  bash "$script"
}

if [[ "$RUN_STOP" == "true" ]]; then
  rohomieo_stop_all
  exit 0
fi

if [[ "$RUN_SETUP" == "true ]]; then
  case "$TARGET" in
    linux)  run_setup linux ;;
    wsl)    run_setup wsl ;;
    macos)  run_setup macos ;;
    all)
      export ROHOMIEO_SKIP_WINDOWS=0
      run_setup wsl
      ;;
    windows)
      cat <<EOF

Run on Windows (PowerShell):

  cd $ROOT
  powershell -ExecutionPolicy Bypass -File .\\scripts\\setup-windows.ps1
  powershell -File .\\scripts\\start-windows-host.ps1

EOF
      ;;
  esac
fi

if [[ "$RUN_START" == "true" ]]; then
  resolve_target
  fg="false"
  [[ "$RUN_FOREGROUND" == "true" ]] && fg="true"
  rohomieo_start_platform "$TARGET" "$fg"
fi
