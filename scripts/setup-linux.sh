#!/usr/bin/env bash
# Native Linux setup — full host + signaling (X11/Wayland via scrap).
set -euo pipefail
ROHOMIEO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT ROHOMIEO_PLATFORM=linux
# shellcheck source=lib/setup-common.sh
source "$ROHOMIEO_ROOT/scripts/lib/setup-common.sh"

setup_info "Rohomieo Linux setup"
setup_ensure_lf

install_os_packages() {
  if command -v apt-get &>/dev/null; then
    setup_apt_build_deps
  elif command -v dnf &>/dev/null; then
    setup_info "Installing packages (dnf)..."
    sudo dnf install -y gcc gcc-c++ make pkg-config git openssl-devel \
      libX11-devel libxcb-devel libxdo-devel nodejs npm
    setup_ok "dnf packages"
  elif command -v pacman &>/dev/null; then
    setup_info "Installing packages (pacman)..."
    sudo pacman -S --needed --noconfirm base-devel pkg-config git openssl \
      libx11 libxcb libxdo nodejs npm
    setup_ok "pacman packages"
  else
    setup_warn "Unknown package manager — install Rust, Node, X11/xcb/xdo dev headers manually"
  fi
}

install_os_packages
setup_install_rust
setup_install_node
setup_gen_certs
setup_build_web
setup_build_rust true
setup_write_env
setup_write_wrappers
setup_install_systemd_user
setup_print_footer linux
