#!/usr/bin/env bash
# Send Wake-on-LAN magic packet (Phase 3 stub).
# Usage: ./scripts/wake-on-lan.sh AA:BB:CC:DD:EE:FF [broadcast]
set -euo pipefail
MAC="${1:?MAC address required, e.g. AA:BB:CC:DD:EE:FF}"
BROADCAST="${2:-255.255.255.255}"
PORT=9

# Normalize MAC to 12 hex chars
MAC_HEX=$(echo "$MAC" | tr -d ':.-' | tr '[:upper:]' '[:lower:]')
if [[ ${#MAC_HEX} -ne 12 ]]; then
  echo "invalid MAC: $MAC"
  exit 1
fi

PACKET=$(printf '%.12s' "$(printf '%0.sFF' {1..6})")$MAC_HEX
# Repeat MAC 16 times
DATA=$(printf '%0.s'"$MAC_HEX" {1..16})
FULL=$(printf '%.12s' "$(printf '%0.sFF' {1..6})")$DATA

python3 - <<PY
import socket
mac = bytes.fromhex("$MAC_HEX")
packet = b"\xff" * 6 + mac * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.sendto(packet, ("$BROADCAST", $PORT))
print(f"WoL packet sent to $BROADCAST:$PORT for $MAC")
PY
