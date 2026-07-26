#!/usr/bin/env bash
# Stage binaries on NTFS (no overwrite of running exes), then elevate once:
# kill → promote staging → allow (firewall/SAC/sign) → start.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT="$ROOT"

detect_win_user() {
  if [[ -n "${WIN_USER:-}" ]]; then echo "$WIN_USER"; return; fi
  local u=""
  if command -v pwsh.exe &>/dev/null; then
    u=$(pwsh.exe -NoProfile -Command '$env:USERNAME' 2>/dev/null | tr -d '\r')
  elif command -v powershell.exe &>/dev/null; then
    u=$(powershell.exe -NoProfile -Command '$env:USERNAME' 2>/dev/null | tr -d '\r')
  elif command -v pwsh &>/dev/null; then
    u=$(pwsh -NoProfile -Command '$env:USERNAME' 2>/dev/null | tr -d '\r')
  fi
  if [[ -z "$u" ]] && [[ -d /mnt/c/Users ]]; then
    u=$(ls /mnt/c/Users 2>/dev/null | grep -Ev '^(Public|Default|Default User|All Users|desktop.ini)$' | head -1 || true)
  fi
  echo "${u:-josep}"
}

WIN_USER="$(detect_win_user)"
RUN="/mnt/c/Users/${WIN_USER}/AppData/Local/rohomieo-run"
STAGE="$RUN/staging"
SRC="$ROOT/target/release"

[[ -f "$SRC/rohomieo-signaling.exe" ]] || {
  echo "Missing binaries — run: ./scripts/build-windows-host.sh"
  exit 1
}

# shellcheck source=lib/bundle-windows-runtime.sh
source "$ROOT/scripts/lib/bundle-windows-runtime.sh"

rm -rf "$STAGE"
mkdir -p "$STAGE/web/dist" "$STAGE/certs" "$RUN"
for f in rohomieo-signaling.exe rohomieo-host.exe libunwind.dll libc++.dll libwinpthread-1.dll; do
  [[ -f "$SRC/$f" ]] && cp -f "$SRC/$f" "$STAGE/"
done
cp -a "$ROOT/web/dist/." "$STAGE/web/dist/"
cp -f "$ROOT/infra/certs/cert.pem" "$ROOT/infra/certs/key.pem" "$STAGE/certs/"

# Also refresh non-locked assets in live run dir now
mkdir -p "$RUN/web/dist" "$RUN/certs"
cp -a "$ROOT/web/dist/." "$RUN/web/dist/" 2>/dev/null || true
cp -f "$ROOT/infra/certs/cert.pem" "$ROOT/infra/certs/key.pem" "$RUN/certs/" 2>/dev/null || true

echo "ok staged -> C:\\Users\\${WIN_USER}\\AppData\\Local\\rohomieo-run\\staging"
