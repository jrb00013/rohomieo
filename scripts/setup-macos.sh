#!/usr/bin/env bash
# macOS setup — Homebrew deps, full host + signaling.
set -euo pipefail
ROHOMIEO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT ROHOMIEO_PLATFORM=macos
# shellcheck source=lib/setup-common.sh
source "$ROHOMIEO_ROOT/scripts/lib/setup-common.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  setup_err "setup-macos.sh requires macOS"
  exit 1
fi

setup_info "Rohomieo macOS setup"
setup_ensure_lf

if ! command -v brew &>/dev/null; then
  setup_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
setup_ok "Homebrew"

if ! xcode-select -p &>/dev/null; then
  setup_info "Installing Xcode Command Line Tools..."
  xcode-select --install 2>/dev/null || true
  setup_warn "Complete the CLT dialog if shown, then re-run setup-macos.sh"
fi

setup_info "Installing brew packages..."
brew install pkg-config openssl node 2>/dev/null || brew install pkg-config openssl node
setup_install_wireguard
# Prefer rustup over brew rust if needed
if ! command -v cargo &>/dev/null; then
  brew install rustup-init 2>/dev/null || true
  rustup-init -y --default-toolchain stable 2>/dev/null || setup_install_rust
else
  setup_ok "Rust $(rustc --version)"
fi

setup_source_cargo
setup_install_node
setup_gen_certs
setup_build_web
setup_build_rust true
setup_write_env
setup_write_wrappers
setup_install_launchd_user

echo ""
setup_warn "macOS permissions required before host works:"
setup_warn "  System Settings -> Privacy & Security -> Screen Recording -> allow rohomieo-host"
setup_warn "  System Settings -> Privacy & Security -> Accessibility -> allow rohomieo-host"
echo ""

setup_print_footer macos
