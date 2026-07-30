#!/usr/bin/env bash
# Print a phone invite: web-UI join URL + terminal QR (no file:// HTML).
# Usage: print-invite-qr.sh <join-url>
set -euo pipefail
JOIN="${1:-}"
if [[ -z "$JOIN" ]]; then
  echo "usage: $0 <https://host:8443/?s=…&p=…&auto=1…>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/var/run"
printf '%s\n' "$JOIN" >"$ROOT/var/run/invite.url"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Phone invite (opens the Rohomieo web UI)"
echo "════════════════════════════════════════════════════════"
echo "  $JOIN"
echo "════════════════════════════════════════════════════════"
echo "  Treat this link like a password (session + PIN + TURN)."
echo "════════════════════════════════════════════════════════"

printed=false
if command -v qrencode >/dev/null 2>&1; then
  if qrencode -t ansiutf8 "$JOIN"; then
    printed=true
  fi
fi

if [[ "$printed" != "true" ]]; then
  VENV="$ROOT/var/qr-venv"
  if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV" >/dev/null 2>&1 || true
    if [[ -x "$VENV/bin/pip" ]]; then
      "$VENV/bin/pip" install -q qrcode >/dev/null 2>&1 || true
    fi
  elif ! "$VENV/bin/python" -c 'import qrcode' 2>/dev/null; then
    "$VENV/bin/pip" install -q qrcode >/dev/null 2>&1 || true
  fi
  if [[ -x "$VENV/bin/python" ]] && "$VENV/bin/python" -c 'import qrcode' 2>/dev/null; then
    if JOIN_URL="$JOIN" "$VENV/bin/python" - <<'PY'
import os
import qrcode
qr = qrcode.QRCode(border=1)
qr.add_data(os.environ["JOIN_URL"])
qr.make(fit=True)
qr.print_ascii(invert=True)
PY
    then
      printed=true
    fi
  fi
fi

if [[ "$printed" != "true" ]]; then
  echo "  (QR: install qrencode, or host window prints one for the same link)"
fi
echo ""
