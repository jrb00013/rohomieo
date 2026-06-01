#!/usr/bin/env bash
# Copy exes + DLLs + web + certs to %LOCALAPPDATA%\rohomieo-run (native path, no UNC).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROHOMIEO_ROOT="$ROOT"

WIN_USER="${WIN_USER:-josep}"
RUN="/mnt/c/Users/${WIN_USER}/AppData/Local/rohomieo-run"
SRC="$ROOT/target/release"

[[ -f "$SRC/rohomieo-signaling.exe" ]] || {
  echo "Missing binaries — run: ./scripts/build-windows-host.sh"
  exit 1
}

# shellcheck source=lib/bundle-windows-runtime.sh
source "$ROOT/scripts/lib/bundle-windows-runtime.sh"

rm -rf "$RUN/certs"
mkdir -p "$RUN/web/dist" "$RUN/certs"
for f in rohomieo-signaling.exe rohomieo-host.exe libunwind.dll libc++.dll libwinpthread-1.dll; do
  [[ -f "$SRC/$f" ]] && cp -f "$SRC/$f" "$RUN/"
done
cp -a "$ROOT/web/dist/." "$RUN/web/dist/"
cp -f "$ROOT/infra/certs/cert.pem" "$ROOT/infra/certs/key.pem" "$RUN/certs/"

echo "ok synced -> C:\\Users\\${WIN_USER}\\AppData\\Local\\rohomieo-run"
