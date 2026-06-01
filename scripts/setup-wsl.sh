#!/usr/bin/env bash
# WSL2 setup — signaling + web in WSL; defers desktop capture to Windows host (setup-windows.ps1).
set -euo pipefail
ROHOMIEO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT ROHOMIEO_PLATFORM=wsl
# shellcheck source=lib/setup-common.sh
source "$ROHOMIEO_ROOT/scripts/lib/setup-common.sh"

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  setup_warn "Not WSL — use ./scripts/setup-linux.sh instead"
  exec "$ROHOMIEO_ROOT/scripts/setup-linux.sh"
fi

setup_info "Rohomieo WSL setup (signaling in WSL + Windows host)"
setup_ensure_lf

# Same deps as Linux (signaling + optional X11 host for testing)
if command -v apt-get &>/dev/null; then
  setup_info "Installing WSL packages (apt, needs sudo)..."
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential pkg-config curl git ca-certificates openssl \
    libx11-dev libxcb1-dev libxcb-shm0-dev libxcb-randr0-dev libxdo-dev \
    nodejs npm
  setup_ok "apt packages"
fi

setup_install_rust
setup_install_node
setup_gen_certs
setup_build_web
setup_source_cargo
cd "$ROHOMIEO_ROOT"
setup_info "Building rohomieo-signaling (release)..."
cargo build --release -p rohomieo-signaling
setup_warn "Building optional WSL host (cannot capture Windows desktop)..."
cargo build --release -p rohomieo-host 2>/dev/null && setup_ok "rohomieo-host (WSL/X11 only)" || \
  setup_warn "rohomieo-host skipped — use Windows .exe for your desktop"

setup_write_env
setup_write_wrappers
setup_install_systemd_user

# Windows companion (MSVC, host.exe, start scripts)
if [[ "${ROHOMIEO_SKIP_WINDOWS:-}" != "1" ]]; then
  setup_invoke_windows
else
  setup_warn "Skipped Windows setup (ROHOMIEO_SKIP_WINDOWS=1)"
fi

setup_print_footer wsl
