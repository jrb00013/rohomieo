#!/usr/bin/env bash
# Rohomieo one-shot installer — auto-detect platform, install deps, build,
# Windows allow (firewall/Defender/sign/SAC) + start. No extra flags needed.
#
#   ./install.sh              # full install + Windows allow + start
#   ./install.sh --build-only # deps + build, no start
#   ./install.sh --start-only # start existing build (still auto-allows Windows)
#
# PowerShell from bash (auto-picked):
#   pwsh -File ./myscript.ps1              # cross-platform PowerShell Core
#   powershell.exe -File ./myscript.ps1    # Windows built-in (WSL / Git Bash / Cygwin)
#
# Env:
#   ROHOMIEO_SKIP_WIREGUARD=1   skip WireGuard
#   ROHOMIEO_SKIP_WINDOWS=1     WSL: skip Windows bridge (signaling only in WSL)
#   WIN_USER=...                Windows username for sync (default: auto)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROHOMIEO_ROOT="$ROOT"

# shellcheck source=scripts/lib/setup-common.sh
source "$ROOT/scripts/lib/setup-common.sh"
# shellcheck source=scripts/lib/setup-start.sh
source "$ROOT/scripts/lib/setup-start.sh"

BUILD_ONLY=false
START_ONLY=false

usage() {
  cat <<'EOF'
Rohomieo install (auto-detect)

  ./install.sh              Install deps, build, Windows allow (UAC once), start
  ./install.sh --build-only Deps + build only
  ./install.sh --start-only Start from existing build (auto Windows allow)

Windows allow prefers the RohomieoBroker LocalSystem service (named pipe).
First time: approve UAC to install the service. Later: no prompt.
Fallback: install-allow.ps1 / scheduled task. Revoke broker:
  powershell -File scripts/windows/install-broker.ps1 -Uninstall

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help) usage; exit 0 ;;
    --build-only) BUILD_ONLY=true; shift ;;
    --start-only|--allow|--start) START_ONLY=true; shift ;;  # --allow kept as alias
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

detect_platform() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo linux ;;
  esac
}

PLATFORM="$(detect_platform)"
export ROHOMIEO_PLATFORM="$PLATFORM"

install_info()  { echo -e "${CYAN}==> install:${NC} $*"; }
install_ok()    { echo -e "${GREEN}ok${NC}  $*"; }
install_warn()  { echo -e "${YELLOW}!${NC}   $*"; }
install_err()   { echo -e "${RED}ERROR:${NC} $*" >&2; }

# apt without failing hard when passwordless sudo is unavailable and packages exist
install_apt_deps() {
  command -v apt-get &>/dev/null || return 0
  local pkgs=(
    build-essential pkg-config curl git ca-certificates openssl
    libx11-dev libxcb1-dev libxcb-shm0-dev libxcb-randr0-dev libxdo-dev
  )
  local need_node=false
  if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
    need_node=true
    pkgs+=(nodejs npm)
  fi

  local missing=()
  local p
  for p in "${pkgs[@]}"; do
    # package names with :amd64 etc — dpkg -s wants bare name sometimes
    if ! dpkg -s "$p" &>/dev/null && ! dpkg -s "${p%%:*}" &>/dev/null; then
      missing+=("$p")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    install_ok "apt build deps present"
    $need_node || install_ok "Node $(node --version 2>/dev/null || echo ok)"
    return 0
  fi

  install_info "Installing apt packages: ${missing[*]}"
  if sudo -n true 2>/dev/null; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    install_ok "apt packages"
  else
    install_warn "sudo needs a password for: ${missing[*]}"
    if sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"; then
      install_ok "apt packages"
    else
      install_err "Could not install apt deps — enter sudo password and re-run ./install.sh"
      return 1
    fi
  fi
}

install_fix_signaling_router() {
  # axum no longer allows nest_service("/") — keep install resilient if tree regresses
  local f="$ROOT/crates/signaling/src/main.rs"
  [[ -f "$f" ]] || return 0
  if grep -q 'nest_service("/")' "$f" 2>/dev/null; then
    install_info "Fixing axum root nest_service → fallback_service"
    sed -i 's/\.nest_service("\/", serve_dir)/.fallback_service(serve_dir)/' "$f"
    install_ok "signaling router fix"
  fi
}

install_write_env() {
  setup_write_env
  # systemd EnvironmentFile cannot use `export` — also write KEY=value sidecar
  local sys="$ROOT/.env.rohomieo.systemd"
  {
    echo "# Generated for systemd EnvironmentFile= (no export)"
    echo "ROHOMIEO_ROOT=$ROOT"
    echo "ROHOMIEO_PLATFORM=$PLATFORM"
    echo "ROHOMIEO_BIND=${ROHOMIEO_BIND:-0.0.0.0:8443}"
    echo "ROHOMIEO_SIGNALING_URL=${ROHOMIEO_SIGNALING_URL:-wss://127.0.0.1:8443/ws}"
    echo "ROHOMIEO_WEB_ROOT=$ROOT/web/dist"
    echo "ROHOMIEO_CERT=$ROOT/infra/certs/cert.pem"
    echo "ROHOMIEO_KEY=$ROOT/infra/certs/key.pem"
  } >"$sys"
  # Point user unit at systemd-friendly file
  if [[ -f "$HOME/.config/systemd/user/rohomieo-signaling.service" ]]; then
    sed -i "s|EnvironmentFile=-.*\.env\.rohomieo|EnvironmentFile=-$sys|" \
      "$HOME/.config/systemd/user/rohomieo-signaling.service" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  install_ok "env files"
}

detect_win_user() {
  if [[ -n "${WIN_USER:-}" ]]; then
    echo "$WIN_USER"
    return
  fi
  local u=""
  if setup_powershell_windows_bin &>/dev/null; then
    u=$(setup_ps_windows_command '$env:USERNAME' 2>/dev/null | tr -d '\r')
  fi
  if [[ -z "$u" ]] && [[ -d /mnt/c/Users ]]; then
    # Prefer non-default profiles that look like a real user
    u=$(ls /mnt/c/Users 2>/dev/null | grep -Ev '^(Public|Default|Default User|All Users|desktop.ini)$' | head -1 || true)
  fi
  echo "${u:-josep}"
}

stop_windows_rohomieo() {
  setup_powershell_windows_bin &>/dev/null || return 0
  # Force-kill so sync can overwrite locked .exe files
  setup_ps_windows_command \
    "Get-Process rohomieo-signaling,rohomieo-host -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 1; cmd /c 'taskkill /F /IM rohomieo-signaling.exe /T 2>nul & taskkill /F /IM rohomieo-host.exe /T 2>nul' | Out-Null" \
    2>/dev/null || true
  sleep 2
}

# WSL/Windows: sync + elevated allow + start (always — no separate --allow step)
start_wsl_windows_stack() {
  if [[ "${ROHOMIEO_SKIP_WINDOWS:-}" == "1" ]]; then
    systemctl --user start rohomieo-signaling.service 2>/dev/null || rohomieo_start_signaling_bg
    return 0
  fi
  WIN_USER="$(detect_win_user)"
  export WIN_USER
  stop_port_8443_conflicts
  if [[ ! -f "$ROOT/target/release/rohomieo-host.exe" ]] || [[ ! -f "$ROOT/target/release/rohomieo-signaling.exe" ]]; then
    build_windows_from_wsl || return 1
  else
    if [[ ! -f "$ROOT/target/release/rohomieo-broker.exe" ]]; then
      "$ROOT/scripts/build-windows-broker.sh" || install_warn "Broker build skipped"
    fi
    install_info "Staging Windows build (NTFS)..."
    WIN_USER="$WIN_USER" "$ROOT/scripts/sync-windows-run.sh" || return 1
  fi
  install_info "Windows allow + start (broker service preferred; UAC once to install)"
  invoke_windows_allow || {
    install_warn "Elevated allow failed — trying run-bridge.ps1"
    rohomieo_start_windows_bridge || true
  }
}


stop_port_8443_conflicts() {
  # Prefer Rohomieo's :8443 — stop stale WSL signaling (old path or this path)
  stop_windows_rohomieo
  if command -v systemctl &>/dev/null; then
    systemctl --user stop rohomieo-signaling.service 2>/dev/null || true
  fi
  local pid
  pid=$(ss -tlnp 2>/dev/null | awk '/:8443/ {print}' | grep -oP 'pid=\K[0-9]+' | head -1 || true)
  if [[ -n "${pid:-}" ]]; then
    local cmd
    cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
    if [[ "$cmd" == *rohomieo* ]]; then
      install_info "Stopping existing rohomieo on :8443 (pid $pid)"
      kill "$pid" 2>/dev/null || true
      sleep 1
    else
      install_warn "Port 8443 in use by $cmd (pid $pid) — Rohomieo needs this port"
    fi
  fi
}

# Resolve Windows path to rohomieo-broker-ctl.exe (Program Files or run dir)
broker_ctl_win_path() {
  local win_user run_linux
  win_user="$(detect_win_user)"
  run_linux="/mnt/c/Users/${win_user}/AppData/Local/rohomieo-run"
  if [[ -f "/mnt/c/Program Files/Rohomieo/rohomieo-broker-ctl.exe" ]]; then
    echo "/mnt/c/Program Files/Rohomieo/rohomieo-broker-ctl.exe"
    return 0
  fi
  if [[ -f "$run_linux/rohomieo-broker-ctl.exe" ]]; then
    echo "$run_linux/rohomieo-broker-ctl.exe"
    return 0
  fi
  return 1
}

broker_ping() {
  local ctl
  ctl=$(broker_ctl_win_path) || return 1
  "$ctl" PING 2>/dev/null | tr -d '\r' | grep -q '^OK'
}

# Prefer LocalSystem broker service (no UAC after one-time install-broker.ps1)
invoke_windows_allow_via_broker() {
  local win_user run_linux run_dir ctl host_w sig_w web_w cert_w key_w
  win_user="$(detect_win_user)"
  run_linux="/mnt/c/Users/${win_user}/AppData/Local/rohomieo-run"
  run_dir=$(wslpath -w "$run_linux" 2>/dev/null || echo "C:\\Users\\${win_user}\\AppData\\Local\\rohomieo-run")
  ctl=$(broker_ctl_win_path) || return 1
  broker_ping || return 1

  install_info "Windows allow via RohomieoBroker service (no UAC)"

  # Promote staging if present (unprivileged copy is fine when exes aren't locked)
  if [[ -f "$run_linux/staging/rohomieo-signaling.exe" ]]; then
    "$ctl" KILL_ALL >/dev/null 2>&1 || true
    sleep 1
    for f in rohomieo-signaling.exe rohomieo-host.exe libunwind.dll libc++.dll libwinpthread-1.dll; do
      [[ -f "$run_linux/staging/$f" ]] && cp -f "$run_linux/staging/$f" "$run_linux/$f"
    done
    if [[ -d "$run_linux/staging/web/dist" ]]; then
      mkdir -p "$run_linux/web/dist"
      cp -a "$run_linux/staging/web/dist/." "$run_linux/web/dist/" 2>/dev/null || true
    fi
    if [[ -d "$run_linux/staging/certs" ]]; then
      mkdir -p "$run_linux/certs"
      cp -f "$run_linux/staging/certs/"* "$run_linux/certs/" 2>/dev/null || true
    fi
  fi

  host_w="${run_dir}\\rohomieo-host.exe"
  sig_w="${run_dir}\\rohomieo-signaling.exe"
  web_w="${run_dir}\\web\\dist"
  cert_w="${run_dir}\\certs\\cert.pem"
  key_w="${run_dir}\\certs\\key.pem"

  "$ctl" FIREWALL_ADD || install_warn "broker FIREWALL_ADD failed"
  "$ctl" DEFENDER_ADD "$run_dir" || true
  "$ctl" KILL_ALL || true
  sleep 1

  if ! "$ctl" START_SIGNALING "$sig_w" --bind 0.0.0.0:8443 --web-root "$web_w" --cert "$cert_w" --key "$key_w"; then
    install_warn "broker START_SIGNALING failed"
    return 1
  fi
  local i ready=0
  for i in $(seq 1 30); do
    if setup_ps_windows_command \
      "if (Get-NetTCPConnection -LocalPort 8443 -State Listen -EA SilentlyContinue) { 'yes' }" \
      2>/dev/null | grep -q yes; then
      ready=1
      break
    fi
    sleep 1
  done
  [[ "$ready" -eq 1 ]] || {
    install_warn "signaling did not open :8443"
    return 1
  }

  if ! "$ctl" START_HOST "$host_w" --signaling wss://127.0.0.1:8443/ws; then
    install_warn "broker START_HOST failed"
    return 1
  fi
  install_ok "Windows allow + host via RohomieoBroker (no UAC)"
  return 0
}

# One-time UAC: install LocalSystem broker service
invoke_install_broker_uac() {
  local ps_win win_user run_linux elev elev_w script_w
  ps_win=$(setup_powershell_windows_bin) || return 1
  win_user="$(detect_win_user)"
  run_linux="/mnt/c/Users/${win_user}/AppData/Local/rohomieo-run"
  mkdir -p "$run_linux"
  cp -f "$ROOT/scripts/windows/install-broker.ps1" "$run_linux/install-broker.ps1"
  sed -i 's/\r$//' "$run_linux/install-broker.ps1" 2>/dev/null || true
  # Stage broker binaries into run dir for the installer to find
  for f in rohomieo-broker.exe rohomieo-broker-ctl.exe; do
    [[ -f "$ROOT/target/release/$f" ]] && cp -f "$ROOT/target/release/$f" "$run_linux/$f"
  done
  if [[ ! -f "$run_linux/rohomieo-broker.exe" ]]; then
    install_warn "Broker not built — run ./scripts/build-windows-broker.sh"
    return 1
  fi
  script_w=$(wslpath -w "$run_linux/install-broker.ps1")
  elev="$run_linux/elevate-broker.ps1"
  cat >"$elev" <<'ELEV'
$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Rohomieo Broker — approve UAC (once)'
Write-Host 'Install RohomieoBroker service (one UAC). Later installs need no elevation.' -ForegroundColor Cyan
$script = Join-Path $env:LOCALAPPDATA 'rohomieo-run\install-broker.ps1'
$p = Start-Process -FilePath (Get-Command powershell.exe).Source -Verb RunAs -PassThru -Wait -ArgumentList @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script
)
exit $(if ($p) { $p.ExitCode } else { 1 })
ELEV
  elev_w=$(wslpath -w "$elev")
  install_info "Installing RohomieoBroker — approve UAC once"
  "$ps_win" -NoProfile -Command \
    "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','$elev_w') -Wait" \
    || true
  sleep 2
  broker_ping
}

invoke_windows_allow() {
  # 1) Broker already installed → silent path
  if invoke_windows_allow_via_broker; then
    return 0
  fi

  # 2) Broker binaries present but service missing → one UAC to install service
  local win_user run_linux
  win_user="$(detect_win_user)"
  run_linux="/mnt/c/Users/${win_user}/AppData/Local/rohomieo-run"
  if [[ -f "$ROOT/target/release/rohomieo-broker.exe" ]] || [[ -f "$run_linux/rohomieo-broker.exe" ]]; then
    if invoke_install_broker_uac; then
      if invoke_windows_allow_via_broker; then
        return 0
      fi
    fi
    install_warn "Broker install/start failed — falling back to install-allow.ps1"
  fi

  local ps_win
  ps_win=$(setup_powershell_windows_bin) || {
    install_warn "PowerShell not found — install pwsh, or use powershell.exe on WSL/Windows"
    return 1
  }
  local run_dir
  run_dir=$(wslpath -w "$run_linux" 2>/dev/null || echo "C:\\Users\\${win_user}\\AppData\\Local\\rohomieo-run")
  mkdir -p "$run_linux"

  # Elevated admin cannot read \\wsl.localhost\... — copy scripts onto NTFS first
  cp -f "$ROOT/scripts/windows/install-allow.ps1" "$run_linux/install-allow.ps1"
  sed -i 's/\r$//' "$run_linux/install-allow.ps1" 2>/dev/null || true

  local marker="$run_linux/.install-allow.exit"
  local logf="$run_linux/install-allow.log"
  rm -f "$marker" 2>/dev/null || true

  local wrap wrap_w
  wrap="$run_linux/install-allow-wrap.ps1"
  cat >"$wrap" <<EOF
\$ErrorActionPreference = 'Continue'
\$run = '$run_dir'
\$marker = Join-Path \$run '.install-allow.exit'
\$log = Join-Path \$run 'install-allow.log'
\$script = Join-Path \$run 'install-allow.ps1'
Try {
  & \$script -RunDir \$run *>&1 | ForEach-Object {
    \$line = \$_.ToString()
    Write-Host \$line
    Add-Content -Path \$log -Value \$line -Encoding utf8
  }
  \$code = \$LASTEXITCODE
  if (\$null -eq \$code) { \$code = 0 }
} Catch {
  \$_ | Out-String | Add-Content -Path \$log -Encoding utf8
  \$code = 1
}
Set-Content -Path \$marker -Value \$code -Encoding ASCII
exit \$code
EOF
  wrap_w=$(wslpath -w "$wrap")

  local schtasks="/mnt/c/Windows/System32/schtasks.exe"
  local task_name="RohomieoElevatedAllow"
  local used_saved_task=0

  # Prefer saved elevated task (no UAC) — registered on first successful allow
  if [[ -x "$schtasks" ]] && "$schtasks" /Query /TN "$task_name" &>/dev/null; then
    install_info "Windows allow via saved task (no UAC)…"
    if "$schtasks" /Run /TN "$task_name" &>/dev/null; then
      used_saved_task=1
    else
      install_warn "Saved elevated task failed to start — falling back to UAC"
    fi
  fi

  if [[ "$used_saved_task" -eq 0 ]]; then
    # First time (or task missing): visible window + UAC once
    local elev="$run_linux/elevate-allow.ps1"
    cat >"$elev" <<'ELEV'
$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Rohomieo install — approve UAC (once)'
Write-Host 'Rohomieo: approve UAC once. Later installs skip this prompt.' -ForegroundColor Cyan
$wrap = Join-Path $env:LOCALAPPDATA 'rohomieo-run\install-allow-wrap.ps1'
try {
  $p = Start-Process -FilePath (Get-Command powershell.exe).Source -Verb RunAs -PassThru -Wait -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrap
  )
  if (-not $p) { exit 1 }
  exit $p.ExitCode
} catch {
  Write-Host $_ -ForegroundColor Red
  Start-Sleep -Seconds 5
  exit 1
}
ELEV
    local elev_w
    elev_w=$(wslpath -w "$elev")

    install_info "Windows allow — approve UAC once (saves elevation for next time)"
    "$ps_win" -NoProfile -Command \
      "Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','$elev_w') -Wait" \
      || true
  fi

  # Wait for marker from wrap (UAC path or scheduled task)
  local waited=0
  while [[ ! -f "$marker" && $waited -lt 180 ]]; do
    sleep 2
    waited=$((waited + 2))
  done
  if [[ ! -f "$marker" ]]; then
    if [[ "$used_saved_task" -eq 1 ]]; then
      install_warn "No completion after ${waited}s from saved task — try: schtasks /Delete /TN $task_name /F then re-run ./install.sh"
    else
      install_warn "No UAC completion after ${waited}s — click Yes on the UAC box, or re-run ./install.sh"
    fi
    return 1
  fi

  local code="1"
  if [[ -f "$marker" ]]; then
    code=$(tr -d '\r\n' <"$marker")
  fi
  if [[ -f "$logf" ]]; then
    install_info "Windows allow log (tail):"
    tail -n 40 "$logf" | sed 's/\r$//' || true
  fi
  if [[ "$code" == "0" ]]; then
    if [[ "$used_saved_task" -eq 1 ]]; then
      install_ok "Windows allow + host started (no UAC)"
    else
      install_ok "Windows allow + host started (UAC saved for next install)"
    fi
    return 0
  elif [[ "$code" == "2" ]]; then
    install_warn "Signaling up; host blocked — reboot if SAC was switched Off, then re-run ./install.sh"
    return 2
  else
    install_warn "Windows allow exited $code — see $logf / UAC / Smart App Control"
    return 1
  fi
}

build_unix() {
  setup_ensure_lf
  install_apt_deps
  if [[ "${ROHOMIEO_SKIP_WIREGUARD:-}" != "1" ]]; then
    setup_install_wireguard || install_warn "WireGuard optional — same-WiFi still works"
  else
    install_warn "Skipping WireGuard (ROHOMIEO_SKIP_WIREGUARD=1)"
  fi
  setup_install_rust
  setup_source_cargo
  setup_install_node || install_warn "Node missing — web build may fail"
  setup_gen_certs
  install_fix_signaling_router
  if command -v npm &>/dev/null; then
    setup_build_web
  else
    install_err "npm required for web PWA"
    return 1
  fi
  install_info "Building rohomieo-signaling (release)..."
  (cd "$ROOT" && cargo build --release -p rohomieo-signaling)
  install_info "Building rohomieo-host (optional on WSL)..."
  (cd "$ROOT" && cargo build --release -p rohomieo-host) 2>/dev/null || install_warn "WSL host optional — Windows host used for desktop"
  install_write_env
  setup_write_wrappers
  setup_install_systemd_user || true
}

build_windows_from_wsl() {
  install_info "Cross-building Windows .exe (llvm-mingw, no Visual Studio)..."
  mkdir -p "$ROOT/var/log"
  if "$ROOT/scripts/build-windows-host.sh" >>"$ROOT/var/log/windows-build.log" 2>&1; then
    install_ok "Windows exes in target/release/"
  else
    install_err "Windows build failed — see var/log/windows-build.log"
    return 1
  fi
  if "$ROOT/scripts/build-windows-broker.sh" >>"$ROOT/var/log/windows-build.log" 2>&1; then
    install_ok "RohomieoBroker exes in target/release/"
  else
    install_warn "Broker build failed (optional) — see var/log/windows-build.log"
  fi
  export WIN_USER
  WIN_USER="$(detect_win_user)"
  install_info "Sync to C:\\Users\\${WIN_USER}\\AppData\\Local\\rohomieo-run"
  WIN_USER="$WIN_USER" "$ROOT/scripts/sync-windows-run.sh"
}

verify_health() {
  local url="https://127.0.0.1:8443/health"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if setup_powershell_windows_bin &>/dev/null; then
      if setup_ps_windows_command "try { (curl.exe -sk $url) } catch { '' }" 2>/dev/null | grep -q 'ok version'; then
        install_ok "health: $(setup_ps_windows_command "curl.exe -sk $url" 2>/dev/null | tr -d '\r')"
        return 0
      fi
    fi
    if curl -sk --max-time 2 "$url" 2>/dev/null | grep -q 'ok version'; then
      install_ok "health: $(curl -sk --max-time 2 "$url")"
      return 0
    fi
    sleep 1
  done
  install_warn "health check not reachable yet (firewall / WSL NAT / still starting)"
  return 1
}

print_urls() {
  local lan=""
  if setup_powershell_windows_bin &>/dev/null; then
    lan=$(setup_ps_windows_command \
      "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.IPAddress -match '^192\.168\.' -and \$_.InterfaceAlias -notmatch 'WSL|vEthernet' } | Select-Object -First 1).IPAddress" \
      2>/dev/null | tr -d '\r')
  fi
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Rohomieo ready ($PLATFORM)${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
  echo "  Laptop:  https://127.0.0.1:8443  (accept cert warning)"
  [[ -n "$lan" ]] && echo "  Phone:   https://${lan}:8443"
  echo "  Session/PIN: host window (Windows) or host terminal"
  echo "  Stop:    ./setup.sh --stop"
  echo ""
}

# ---------- main ----------
echo ""
echo -e "${GREEN}Rohomieo install${NC} (platform: $PLATFORM)"
echo ""

chmod +x "$ROOT"/scripts/*.sh "$ROOT"/scripts/lib/*.sh 2>/dev/null || true
chmod +x "$ROOT/install.sh" 2>/dev/null || true

# Fast path: start (or re-start) with automatic Windows allow
if [[ "$START_ONLY" == "true" ]]; then
  case "$PLATFORM" in
    wsl) start_wsl_windows_stack ;;
    linux|macos) stop_port_8443_conflicts; rohomieo_start_platform "$PLATFORM" false ;;
    windows)
      install_info "Run: pwsh -File .\\scripts\\windows\\install-allow.ps1"
      exit 0
      ;;
    *) install_err "start not supported on $PLATFORM"; exit 1 ;;
  esac
  verify_health || true
  print_urls
  exit 0
fi

case "$PLATFORM" in
  wsl)
    # Skip heavy rebuild if release binaries already exist (still auto-allows)
    if [[ -x "$ROOT/target/release/rohomieo-signaling" ]] && \
       [[ -f "$ROOT/target/release/rohomieo-host.exe" ]] && \
       [[ -f "$ROOT/web/dist/index.html" ]]; then
      install_ok "build present — install + auto Windows allow/start"
    else
      build_unix
      if [[ "${ROHOMIEO_SKIP_WINDOWS:-}" != "1" ]]; then
        build_windows_from_wsl
      fi
    fi
    if [[ "$BUILD_ONLY" == "true" ]]; then
      install_ok "build-only complete"
      exit 0
    fi
    start_wsl_windows_stack
    ;;
  linux)
    build_unix
    if [[ "$BUILD_ONLY" == "true" ]]; then
      install_ok "build-only complete"
      exit 0
    fi
    stop_port_8443_conflicts
    rohomieo_start_linux false
    ;;
  macos)
    setup_ensure_lf
    setup_install_rust
    setup_source_cargo
    setup_install_node || true
    setup_gen_certs
    install_fix_signaling_router
    setup_build_web
    (cd "$ROOT" && cargo build --release -p rohomieo-signaling -p rohomieo-host)
    install_write_env
    setup_write_wrappers
    if [[ "$BUILD_ONLY" == "true" ]]; then
      install_ok "build-only complete"
      exit 0
    fi
    rohomieo_start_macos false
    ;;
  windows)
    install_info "From PowerShell (allow is built into install-allow):"
    echo "  pwsh -File .\\scripts\\setup-windows.ps1"
    echo "  pwsh -File .\\scripts\\windows\\install-allow.ps1"
    exit 0
    ;;
  *)
    install_err "Unsupported platform: $PLATFORM"
    exit 1
    ;;
esac

verify_health || true
print_urls
