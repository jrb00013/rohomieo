# shellcheck shell=bash
# Start Rohomieo services (WireGuard bridge + signaling + Windows host). Sourced from setup.sh --start

[[ -n "${ROHOMIEO_SETUP_START_LOADED:-}" ]] && return 0
ROHOMIEO_SETUP_START_LOADED=1

: "${ROHOMIEO_ROOT:?}"

setup_start_info()  { echo -e "${CYAN}==> start:${NC} $*"; }
setup_start_ok()    { echo -e "${GREEN}ok${NC}  $*"; }
setup_start_warn()  { echo -e "${YELLOW}!${NC}   $*"; }

rohomieo_ensure_env() {
  # shellcheck source=/dev/null
  [[ -f "$ROHOMIEO_ROOT/.env.rohomieo" ]] && source "$ROHOMIEO_ROOT/.env.rohomieo"
  mkdir -p "$ROHOMIEO_ROOT/var/run" "$ROHOMIEO_ROOT/var/log"
}

# Forward Windows LAN :8443 -> WSL (needs Admin once). Opens UAC if missing.
rohomieo_ensure_lan_portproxy() {
  command -v powershell.exe &>/dev/null || return 0
  local wsl_ip
  wsl_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -n "$wsl_ip" ]] || return 0
  local has_proxy
  has_proxy=$(powershell.exe -NoProfile -Command \
    "(netsh interface portproxy show all | Select-String '8443').Count" 2>/dev/null | tr -d '\r')
  [[ "${has_proxy:-0}" != "0" ]] && return 0
  setup_start_warn "LAN port 8443 not forwarded — run as Administrator (see below)"
  local script_w
  script_w=$(wslpath -w "$ROHOMIEO_ROOT/scripts/windows/enable-phone-access.ps1" 2>/dev/null) || return 0
  powershell.exe -NoProfile -Command \
    "Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','$script_w')" \
    2>/dev/null || true
  echo ""
  echo "  If no UAC prompt, open Admin PowerShell and run:"
  echo "    cd \\\\wsl.localhost\\Ubuntu\\home\\josep\\rohomieo"
  echo "    powershell -ExecutionPolicy Bypass -File .\\scripts\\windows\\enable-phone-access.ps1"
  echo ""
}

rohomieo_pid_running() {
  local pidfile="$1"
  [[ -f "$pidfile" ]] || return 1
  local pid
  pid=$(cat "$pidfile")
  kill -0 "$pid" 2>/dev/null
}

rohomieo_start_signaling_bg() {
  rohomieo_ensure_env
  local pidfile="$ROHOMIEO_ROOT/var/run/signaling.pid"
  if rohomieo_pid_running "$pidfile"; then
    setup_start_ok "signaling already running (pid $(cat "$pidfile"))"
    return 0
  fi
  if [[ ! -x "$ROHOMIEO_ROOT/target/release/rohomieo-signaling" ]]; then
    setup_start_warn "rohomieo-signaling missing — run ./setup.sh --wsl (or --linux) first"
    return 1
  fi
  setup_start_info "signaling → ${ROHOMIEO_BIND:-0.0.0.0:8443}"
  nohup "$ROHOMIEO_ROOT/.local/bin/rohomieo-signaling" \
    >>"$ROHOMIEO_ROOT/var/log/signaling.log" 2>&1 &
  echo $! >"$pidfile"
  sleep 1
  if rohomieo_pid_running "$pidfile"; then
    setup_start_ok "signaling pid $(cat "$pidfile") — log var/log/signaling.log"
  else
    setup_start_warn "signaling failed — see var/log/signaling.log"
    return 1
  fi
}

rohomieo_start_host_bg() {
  rohomieo_ensure_env
  local pidfile="$ROHOMIEO_ROOT/var/run/host.pid"
  if rohomieo_pid_running "$pidfile"; then
    setup_start_ok "host already running (pid $(cat "$pidfile"))"
    return 0
  fi
  if [[ ! -x "$ROHOMIEO_ROOT/target/release/rohomieo-host" ]]; then
    setup_start_warn "rohomieo-host not in WSL — starting Windows host instead"
    rohomieo_start_windows_host_window
    return 0
  fi
  export DISPLAY="${DISPLAY:-:0}"
  setup_start_info "host agent (WSL display)"
  nohup "$ROHOMIEO_ROOT/.local/bin/rohomieo-host" \
    >>"$ROHOMIEO_ROOT/var/log/host.log" 2>&1 &
  echo $! >"$pidfile"
  sleep 1
  setup_start_ok "host pid $(cat "$pidfile") — log var/log/host.log"
}

rohomieo_ensure_windows_host_build() {
  [[ -f "$ROHOMIEO_ROOT/target/release/rohomieo-host.exe" ]] && \
    [[ -f "$ROHOMIEO_ROOT/target/release/rohomieo-signaling.exe" ]] && return 0
  setup_start_info "Building Windows host.exe (llvm-mingw from WSL, no VS)..."
  if "$ROHOMIEO_ROOT/scripts/build-windows-host.sh" >>"$ROHOMIEO_ROOT/var/log/windows-build.log" 2>&1; then
    setup_start_ok "rohomieo-host.exe ready"
  else
    setup_start_warn "host build failed — see var/log/windows-build.log"
    return 1
  fi
}

rohomieo_start_windows_bridge() {
  command -v powershell.exe &>/dev/null || return 0
  rohomieo_ensure_windows_host_build || true
  setup_start_info "Syncing to Windows AppData (exes + DLLs + web)..."
  if ! "$ROHOMIEO_ROOT/scripts/sync-windows-run.sh" >>"$ROHOMIEO_ROOT/var/log/windows-build.log" 2>&1; then
    setup_start_warn "sync failed — run: ./scripts/sync-windows-run.sh"
    return 1
  fi
  setup_start_ok "synced to %LOCALAPPDATA%\\rohomieo-run"
  local bridge_w fw_w
  bridge_w=$(wslpath -w "$ROHOMIEO_ROOT/scripts/windows/run-bridge.ps1" 2>/dev/null) || return 0
  fw_w=$(wslpath -w "$ROHOMIEO_ROOT/scripts/windows/enable-phone-access.ps1" 2>/dev/null) || true
  # One-shot: try Admin firewall + portproxy cleanup (phone uses Windows :8443; portproxy not required)
  if [[ -n "${fw_w:-}" ]]; then
    powershell.exe -NoProfile -Command \
      "Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','$fw_w')" \
      2>/dev/null || true
  fi
  setup_start_info "Starting signaling + host on Windows..."
  powershell.exe -NoProfile -Command \
    "Start-Process powershell -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File','$bridge_w')" \
    2>/dev/null || setup_start_warn "Could not launch run-bridge.ps1"
  sleep 2
}

rohomieo_start_windows_host_window() {
  local win_ps="" script_w=""
  command -v powershell.exe &>/dev/null && win_ps="powershell.exe"
  [[ -n "$win_ps" ]] || return 0
  rohomieo_ensure_windows_host_build
  script_w=$(wslpath -w "$ROHOMIEO_ROOT/scripts/windows/start-host.ps1" 2>/dev/null) || return 0
  setup_start_info "Opening Windows host (new PowerShell window)..."
  "$win_ps" -NoProfile -Command \
    "Start-Process powershell -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File','$script_w')" \
    2>/dev/null || setup_start_warn "Could not launch Windows host — run: powershell -File scripts\\windows\\start-host.ps1"
}

rohomieo_start_windows_stack_window() {
  local win_ps="" script_w=""
  command -v powershell.exe &>/dev/null && win_ps="powershell.exe"
  [[ -n "$win_ps" ]] || return 0
  script_w=$(wslpath -w "$ROHOMIEO_ROOT/scripts/start-windows-host.ps1" 2>/dev/null) || return 0
  setup_start_info "Opening Windows signaling + host (new windows)..."
  "$win_ps" -NoProfile -Command \
    "Start-Process powershell -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File','$script_w')" \
    2>/dev/null || true
}

rohomieo_start_wg_bridge() {
  if [[ "${ROHOMIEO_SKIP_WIREGUARD:-}" == "1" ]]; then
    return 0
  fi
  if ! command -v wg &>/dev/null; then
    setup_start_warn "wg not installed — run ./setup.sh --wsl first"
    return 0
  fi
  if [[ ! -f /etc/wireguard/wg0.conf ]]; then
    setup_start_info "installing wg0.conf... (sudo)"
    if ! "$ROHOMIEO_ROOT/scripts/wireguard-wsl-bridge.sh" install; then
      setup_start_warn "wg0 install skipped (sudo) — same-WiFi still works via LAN IP"
      return 0
    fi
  fi
  if sudo wg show wg0 &>/dev/null; then
    setup_start_ok "WireGuard wg0 already up (10.8.0.1)"
    return 0
  fi
  setup_start_info "WireGuard bridge up... (sudo)"
  if ! "$ROHOMIEO_ROOT/scripts/wireguard-wsl-bridge.sh" up; then
    setup_start_warn "wg0 not up — use Phone WiFi URL or run: sudo ./scripts/wireguard-wsl-bridge.sh up"
  fi
}

rohomieo_start_wsl() {
  local fg="${1:-false}"
  echo ""
  echo -e "${GREEN}Starting Rohomieo (WSL2 bridge)${NC}"
  rohomieo_start_wg_bridge
  if [[ "$fg" == "true" ]]; then
    exec "$ROHOMIEO_ROOT/scripts/start-wsl-bridge.sh"
  fi
  # Phone on Wi-Fi hits Windows LAN IP — run signaling+host on Windows (not WSL portproxy).
  if rohomieo_pid_running "$ROHOMIEO_ROOT/var/run/signaling.pid"; then
    kill "$(cat "$ROHOMIEO_ROOT/var/run/signaling.pid")" 2>/dev/null || true
    rm -f "$ROHOMIEO_ROOT/var/run/signaling.pid"
    setup_start_ok "stopped WSL signaling (using Windows :8443 for LAN)"
  fi
  if rohomieo_pid_running "$ROHOMIEO_ROOT/var/run/host.pid"; then
    kill "$(cat "$ROHOMIEO_ROOT/var/run/host.pid")" 2>/dev/null || true
    rm -f "$ROHOMIEO_ROOT/var/run/host.pid"
  fi
  rohomieo_ensure_windows_host_build || true
  rohomieo_start_windows_bridge
  echo ""
  setup_start_ok "WSL stack running"
  local lan_ip=""
  if command -v powershell.exe &>/dev/null; then
    lan_ip=$(powershell.exe -NoProfile -Command \
      "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.IPAddress -match '^192\.168\.|^10\.' -and \$_.InterfaceAlias -notmatch 'WSL|vEthernet' } | Select-Object -First 1).IPAddress" 2>/dev/null \
      | tr -d '\r')
  fi
  echo "  Laptop:    https://127.0.0.1:8443  (accept self-signed cert)"
  if [[ -n "$lan_ip" ]]; then
    echo "  Phone WiFi: https://${lan_ip}:8443  (signaling runs on Windows)"
  fi
  echo "  Phone VPN:  http://10.8.0.1:8443  (WireGuard on)"
  echo "  Session/PIN: Windows host PowerShell window (build: var/log/windows-build.log)"
  echo "  Stop:      ./setup.sh --stop"
  echo ""
}

rohomieo_start_linux() {
  local fg="${1:-false}"
  if [[ "$fg" == "true" ]]; then
    exec "$ROHOMIEO_ROOT/scripts/start-linux.sh"
  fi
  rohomieo_start_signaling_bg
  rohomieo_start_host_bg
  echo ""
  setup_start_ok "Linux stack running — http://127.0.0.1:8443"
  echo "  Stop: ./setup.sh --stop"
  echo ""
}

rohomieo_start_macos() {
  local fg="${1:-false}"
  if [[ "$fg" == "true" ]]; then
    exec "$ROHOMIEO_ROOT/scripts/start-macos.sh"
  fi
  rohomieo_start_signaling_bg
  rohomieo_start_host_bg
  setup_start_ok "macOS stack running — http://127.0.0.1:8443"
}

rohomieo_start_platform() {
  local platform="${1:-linux}"
  local fg="${2:-false}"
  case "$platform" in
    wsl)   rohomieo_start_wsl "$fg" ;;
    linux) rohomieo_start_linux "$fg" ;;
    macos) rohomieo_start_macos "$fg" ;;
    windows)
      rohomieo_start_windows_stack_window
      setup_start_ok "Launched Windows start script — check new PowerShell windows"
      ;;
    *) setup_start_warn "Unknown platform: $platform" ;;
  esac
}

rohomieo_stop_all() {
  rohomieo_ensure_env
  for name in signaling host; do
    local pidfile="$ROHOMIEO_ROOT/var/run/${name}.pid"
    if rohomieo_pid_running "$pidfile"; then
      kill "$(cat "$pidfile")" 2>/dev/null || true
      rm -f "$pidfile"
      setup_start_ok "stopped $name"
    fi
  done
  if command -v wg &>/dev/null && sudo wg show wg0 &>/dev/null; then
    sudo "$ROHOMIEO_ROOT/scripts/wireguard-wsl-bridge.sh" down 2>/dev/null || \
      sudo wg-quick down wg0 2>/dev/null || true
    setup_start_ok "wg0 down"
  fi
}
