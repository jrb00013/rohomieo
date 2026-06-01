# shellcheck shell=bash
# Shared helpers for setup-linux.sh, setup-wsl.sh, setup-macos.sh
# Source from repo scripts: source "$(dirname "$0")/lib/setup-common.sh"

[[ -n "${ROHOMIEO_SETUP_COMMON_LOADED:-}" ]] && return 0
ROHOMIEO_SETUP_COMMON_LOADED=1

: "${ROHOMIEO_ROOT:?ROHOMIEO_ROOT must be set}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

setup_info()  { echo -e "${CYAN}==>${NC} $*"; }
setup_ok()    { echo -e "${GREEN}ok${NC} $*"; }
setup_warn()  { echo -e "${YELLOW}!${NC} $*"; }
setup_err()   { echo -e "${RED}ERROR:${NC} $*" >&2; }

setup_detect_platform() {
  IS_WSL=false
  IS_LINUX=false
  IS_MACOS=false
  case "$(uname -s)" in
    Darwin) IS_MACOS=true ;;
    Linux)
      IS_LINUX=true
      grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true
      ;;
  esac
}

setup_ensure_lf() {
  # Fix CRLF if repo was checked out on Windows
  local f
  for f in "$ROHOMIEO_ROOT"/setup.sh "$ROHOMIEO_ROOT"/scripts/*.sh; do
    [[ -f "$f" ]] && sed -i 's/\r$//' "$f" 2>/dev/null || true
  done
}

setup_install_rust() {
  if command -v cargo &>/dev/null; then
    setup_ok "Rust $(rustc --version)"
    return
  fi
  setup_info "Installing Rust (rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  setup_ok "Rust installed"
}

setup_source_cargo() {
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
  fi
}

setup_install_node() {
  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    setup_ok "Node $(node --version), npm $(npm --version)"
    return
  fi
  setup_warn "Node/npm not found — install Node 18+ (https://nodejs.org or nvm) then re-run setup"
  return 1
}

# Debian/Ubuntu build deps. Skips apt nodejs/npm if Node is already installed (e.g. NodeSource)
# to avoid: "nodejs : Conflicts: npm"
setup_apt_build_deps() {
  command -v apt-get &>/dev/null || return 0
  local pkgs=(
    build-essential pkg-config curl git ca-certificates openssl
    libx11-dev libxcb1-dev libxcb-shm0-dev libxcb-randr0-dev libxdo-dev
  )
  setup_info "Installing apt build dependencies (sudo)..."
  sudo apt-get update -qq
  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    setup_ok "Using existing Node $(node --version) — not installing apt nodejs/npm"
  else
    setup_info "Installing nodejs from apt (no Node detected)..."
    pkgs+=(nodejs npm)
  fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  setup_ok "apt packages"
}

# WireGuard — VPN for phone access to Rohomieo (see infra/wireguard/README.md)
setup_install_wireguard() {
  if [[ "${ROHOMIEO_SKIP_WIREGUARD:-}" == "1" ]]; then
    setup_warn "Skipping WireGuard (ROHOMIEO_SKIP_WIREGUARD=1)"
    return 0
  fi

  setup_detect_platform
  local platform="${ROHOMIEO_PLATFORM:-linux}"

  if command -v wg &>/dev/null; then
    setup_ok "WireGuard CLI already installed"
  else
    if [[ "$platform" == "wsl" ]] || { $IS_LINUX && command -v apt-get &>/dev/null; }; then
      setup_info "Installing WireGuard tools (apt)..."
      sudo apt-get install -y wireguard-tools 2>/dev/null || \
        sudo apt-get install -y wireguard
    elif command -v dnf &>/dev/null; then
      setup_info "Installing WireGuard (dnf)..."
      sudo dnf install -y wireguard-tools
    elif command -v pacman &>/dev/null; then
      setup_info "Installing WireGuard (pacman)..."
      sudo pacman -S --needed --noconfirm wireguard-tools
    elif [[ "$(uname -s)" == "Darwin" ]]; then
      setup_install_wireguard_macos_brew
    fi
  fi

  if command -v wg &>/dev/null; then
    setup_ok "wg $(wg --version 2>&1 | head -1 || true)"
  else
    setup_warn "wg not in PATH — install WireGuard manually"
  fi

  # WSL: prefer in-WSL VPN bridge (mirrored networking) or fallback to Windows GUI
  if [[ "$platform" == "wsl" ]]; then
    setup_ok "WSL2 WireGuard bridge: ./scripts/wireguard-wsl-bridge.sh install (see infra/wireguard/wsl-bridge/)"
    if [[ "${ROHOMIEO_WG_WINDOWS_GUI:-}" == "1" ]]; then
      setup_install_wireguard_windows_app
    else
      setup_warn "Optional Windows GUI: ROHOMIEO_WG_WINDOWS_GUI=1 ./setup.sh --wsl"
    fi
  elif [[ "$platform" == "linux" ]] && ! $IS_WSL; then
    setup_info "Native Linux can run: sudo wg-quick up wg0 (see infra/wireguard/)"
  fi

  setup_wireguard_gen_keys_if_missing
}

setup_install_wireguard_macos_brew() {
  if ! command -v brew &>/dev/null; then
    setup_warn "Homebrew required for WireGuard on macOS — install brew first"
    return 1
  fi
  setup_info "Installing wireguard-tools (brew)..."
  brew install wireguard-tools
  setup_ok "wireguard-tools"
}

setup_install_wireguard_windows_app() {
  local win_ps=""
  command -v powershell.exe &>/dev/null && win_ps="powershell.exe"
  command -v pwsh.exe &>/dev/null && [[ -z "$win_ps" ]] && win_ps="pwsh.exe"
  [[ -n "$win_ps" ]] || return 0

  setup_info "Installing WireGuard for Windows (winget)..."
  if "$win_ps" -NoProfile -Command \
    "if (Get-Command wireguard -ErrorAction SilentlyContinue) { exit 0 }; \
     if (Get-Command winget -ErrorAction SilentlyContinue) { \
       winget install --id WireGuard.WireGuard -e --accept-package-agreements --accept-source-agreements; \
       exit \$LASTEXITCODE \
     } else { exit 2 }" 2>/dev/null; then
    setup_ok "WireGuard for Windows (GUI) — import tunnel from infra/wireguard/"
  else
    setup_warn "Install WireGuard manually: https://www.wireguard.com/install/"
  fi
}

setup_wireguard_gen_keys_if_missing() {
  command -v wg &>/dev/null || return 0
  local keydir="$ROHOMIEO_ROOT/infra/wireguard/keys"
  if [[ -f "$keydir/server.key" ]]; then
    setup_ok "VPN keys exist in infra/wireguard/keys/"
    return 0
  fi
  setup_info "Generating WireGuard key pairs (server, laptop, phone)..."
  bash "$ROHOMIEO_ROOT/scripts/wireguard-gen-keys.sh"
  setup_ok "keys in infra/wireguard/keys/ — copy into *.conf.example"
}

setup_build_web() {
  setup_info "Building web PWA..."
  (cd "$ROHOMIEO_ROOT/web" && npm ci && npm run build)
  setup_ok "web/dist"
}

setup_gen_certs() {
  if [[ -f "$ROHOMIEO_ROOT/infra/certs/cert.pem" ]]; then
    setup_ok "TLS certs exist"
    return
  fi
  if command -v openssl &>/dev/null; then
    setup_info "Generating dev TLS cert..."
    bash "$ROHOMIEO_ROOT/scripts/gen-dev-cert.sh"
    setup_ok "infra/certs/"
  else
    setup_warn "openssl missing — skip TLS (HTTP only)"
  fi
}

setup_build_rust() {
  local build_host="${1:-true}"
  setup_source_cargo
  cd "$ROHOMIEO_ROOT"
  setup_info "Building rohomieo-signaling (release)..."
  cargo build --release -p rohomieo-signaling
  if [[ "$build_host" == "true" ]]; then
    setup_info "Building rohomieo-host (release)..."
    cargo build --release -p rohomieo-host
  else
    setup_warn "Skipping rohomieo-host on this platform step (use Windows host on WSL)"
  fi
  setup_ok "target/release/"
}

setup_write_env() {
  local extra_env="${1:-}"
  mkdir -p "$ROHOMIEO_ROOT/.local/bin" "$ROHOMIEO_ROOT/var/log"
  local win_ip=""
  if [[ "${ROHOMIEO_PLATFORM:-}" == "wsl" ]] && command -v ip &>/dev/null; then
    win_ip=$(ip route show 2>/dev/null | awk '/default/ {print $3; exit}')
  fi
  cat >"$ROHOMIEO_ROOT/.env.rohomieo" <<EOF
# Generated by Rohomieo setup — source: source .env.rohomieo
export ROHOMIEO_ROOT="$ROHOMIEO_ROOT"
export ROHOMIEO_PLATFORM="${ROHOMIEO_PLATFORM:-linux}"
export ROHOMIEO_BIND="${ROHOMIEO_BIND:-0.0.0.0:8443}"
export ROHOMIEO_SIGNALING_URL="${ROHOMIEO_SIGNALING_URL:-ws://127.0.0.1:8443/ws}"
export ROHOMIEO_WEB_ROOT="$ROHOMIEO_ROOT/web/dist"
export ROHOMIEO_CERT="$ROHOMIEO_ROOT/infra/certs/cert.pem"
export ROHOMIEO_KEY="$ROHOMIEO_ROOT/infra/certs/key.pem"
export ROHOMIEO_WSL_WINDOWS_IP="${win_ip:-}"
${extra_env}
EOF
  setup_ok ".env.rohomieo"
}

setup_write_wrappers() {
  cat >"$ROHOMIEO_ROOT/.local/bin/rohomieo-signaling" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"
ARGS=(--bind "${ROHOMIEO_BIND}" --web-root "${ROHOMIEO_WEB_ROOT}")
[[ -f "${ROHOMIEO_CERT:-}" && -f "${ROHOMIEO_KEY:-}" ]] && ARGS+=(--cert "$ROHOMIEO_CERT" --key "$ROHOMIEO_KEY")
exec "$ROOT/target/release/rohomieo-signaling" "${ARGS[@]}" "$@"
WRAP

  cat >"$ROHOMIEO_ROOT/.local/bin/rohomieo-host" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"
exec "$ROOT/target/release/rohomieo-host" --signaling "${ROHOMIEO_SIGNALING_URL}" "$@"
WRAP

  chmod +x "$ROHOMIEO_ROOT/.local/bin/rohomieo-signaling" "$ROHOMIEO_ROOT/.local/bin/rohomieo-host"
  setup_ok "wrappers .local/bin/rohomieo-{signaling,host}"
}

setup_install_systemd_user() {
  command -v systemctl &>/dev/null || return 0
  [[ -d /run/systemd/system ]] || return 0
  mkdir -p "$HOME/.config/systemd/user"
  sed "s|@ROOT@|$ROHOMIEO_ROOT|g; s|@BIN@|$ROHOMIEO_ROOT/.local/bin|g" \
    "$ROHOMIEO_ROOT/infra/systemd/rohomieo-signaling.service.in" \
    >"$HOME/.config/systemd/user/rohomieo-signaling.service"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable rohomieo-signaling.service 2>/dev/null || true
  setup_ok "systemd user unit rohomieo-signaling (systemctl --user start rohomieo-signaling)"
}

setup_install_launchd_user() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  local plist="$HOME/Library/LaunchAgents/com.rohomieo.signaling.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.rohomieo.signaling</string>
  <key>ProgramArguments</key>
  <array>
    <string>$ROHOMIEO_ROOT/.local/bin/rohomieo-signaling</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$ROHOMIEO_ROOT/var/log/signaling.log</string>
  <key>StandardErrorPath</key><string>$ROHOMIEO_ROOT/var/log/signaling.err</string>
</dict></plist>
EOF
  setup_ok "launchd plist com.rohomieo.signaling"
  setup_warn "Load with: launchctl load $plist"
}

setup_invoke_windows() {
  local ps1="$ROHOMIEO_ROOT/scripts/setup-windows.ps1"
  [[ -f "$ps1" ]] || return 0
  local win_ps=""
  command -v powershell.exe &>/dev/null && win_ps="powershell.exe"
  command -v pwsh.exe &>/dev/null && [[ -z "$win_ps" ]] && win_ps="pwsh.exe"
  if [[ -z "$win_ps" ]]; then
    setup_warn "Run on Windows: powershell -File scripts\\setup-windows.ps1"
    return 0
  fi
  setup_info "Windows companion setup (host.exe + MSVC build)..."
  local win_script win_root
  win_script=$(wslpath -w "$ps1" 2>/dev/null) || win_script="$ps1"
  win_root=$(wslpath -w "$ROHOMIEO_ROOT" 2>/dev/null) || win_root="$ROHOMIEO_ROOT"
  if "$win_ps" -NoProfile -ExecutionPolicy Bypass -File "$win_script" -RepoRoot "$win_root"; then
    setup_ok "Windows setup finished"
  else
    setup_warn "Windows setup failed — install VS Build Tools, then run setup-windows.ps1"
  fi
}

setup_print_footer() {
  local platform="${1:-linux}"
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Rohomieo setup complete ($platform)${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  source $ROHOMIEO_ROOT/.env.rohomieo"
  case "$platform" in
    wsl)
      echo "  ./scripts/start-wsl-bridge.sh     # VPN (wg0) + signaling in WSL"
      echo "  ./scripts/wireguard-wsl-bridge.sh up"
      echo "  ./scripts/start-windows-host.ps1  # host on Windows (PowerShell)"
      ;;
    macos)
      echo "  ./scripts/start-macos.sh"
      echo "  Grant Screen Recording + Accessibility for rohomieo-host in System Settings"
      ;;
    linux)
      echo "  ./scripts/start-linux.sh"
      ;;
  esac
  echo "  Browser: http://127.0.0.1:8443"
  echo "  Windows: scripts\\start-windows-host.ps1"
  echo "  WireGuard: infra/wireguard/README.md (keys in infra/wireguard/keys/)"
  echo ""
}
