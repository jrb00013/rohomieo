#!/usr/bin/env bash
# Start signaling in WSL. For Windows desktop capture, run start-windows-host.ps1 on Windows.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"

if [[ ! -x "$ROOT/target/release/rohomieo-signaling" ]]; then
  echo "Run ./scripts/setup-wsl.sh first" >&2
  exit 1
fi

echo "════════════════════════════════════════════════════════"
echo " WSL: starting signaling + web UI only"
echo " For your Windows desktop, also run on Windows:"
echo "   powershell -File scripts\\start-windows-host.ps1"
echo " Or full stack on Windows if signaling is there too."
echo "════════════════════════════════════════════════════════"
echo "Open http://127.0.0.1:8443 (or Windows IP from phone)"
echo ""

"$ROOT/.local/bin/rohomieo-signaling"
