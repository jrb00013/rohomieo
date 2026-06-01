@echo off
:: From WSL:  ./scripts/sync-windows-run.sh  then double-click this, OR  ./setup.sh --start
wsl -e bash -lc "cd ~/rohomieo && ./scripts/sync-windows-run.sh"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-bridge.ps1"
pause
