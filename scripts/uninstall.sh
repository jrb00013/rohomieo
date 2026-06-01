#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
systemctl --user disable rohomieo-signaling.service 2>/dev/null || true
systemctl --user stop rohomieo-signaling.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/rohomieo-signaling.service"
systemctl --user daemon-reload 2>/dev/null || true
echo "Removed systemd user service. Binaries and repo left at $ROOT"
