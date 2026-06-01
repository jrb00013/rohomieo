#!/usr/bin/env bash
# Remove Rohomieo user services (systemd / launchd). Does not delete the repo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if command -v systemctl &>/dev/null; then
  systemctl --user disable rohomieo-signaling.service 2>/dev/null || true
  systemctl --user stop rohomieo-signaling.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/rohomieo-signaling.service"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "Removed systemd user service rohomieo-signaling"
fi

PLIST="$HOME/Library/LaunchAgents/com.rohomieo.signaling.plist"
if [[ -f "$PLIST" ]]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed launchd agent com.rohomieo.signaling"
fi

echo "Binaries and config left at $ROOT (delete manually if desired)"
