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

setup_apt_build_deps
setup_install_wireguard

setup_install_rust
setup_install_node || setup_warn "Web build needs Node — install Node 18+ and run: cd web && npm ci && npm run build"
setup_gen_certs
if command -v npm &>/dev/null; then
  setup_build_web
else
  setup_warn "Skipping web PWA build (no npm). Windows setup-windows.ps1 can build web/dist."
fi
setup_source_cargo
cd "$ROHOMIEO_ROOT"
setup_info "Building rohomieo-signaling (release)..."
cargo build --release -p rohomieo-signaling
setup_info "Building optional WSL host (X11 only — desktop capture uses Windows .exe)..."
if cargo build --release -p rohomieo-host 2>/dev/null; then
  setup_ok "rohomieo-host built in WSL (optional)"
else
  setup_warn "rohomieo-host not built in WSL (expected — use Windows host)"
fi

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

if [[ "${ROHOMIEO_AUTO_START:-}" == "1" ]]; then
  # shellcheck source=lib/setup-start.sh
  source "$ROHOMIEO_ROOT/scripts/lib/setup-start.sh"
  rohomieo_start_wsl false
fi
