# How to use Rohomieo

See also [ROADMAP.md](ROADMAP.md) for planned features.

## 1. Install

| Environment | Command |
|-------------|---------|
| Auto-detect | `./setup.sh` |
| WSL2 | `./setup.sh --wsl` → `scripts/setup-wsl.sh` + Windows `setup-windows.ps1` |
| Linux | `./setup.sh --linux` → `scripts/setup-linux.sh` |
| macOS | `./setup.sh --macos` → `scripts/setup-macos.sh` |
| Windows only | `powershell -File scripts\setup-windows.ps1` |

## 2. Start (same machine test)

| Platform | Command |
|----------|---------|
| Windows | `powershell -File scripts\start-windows-host.ps1` |
| WSL | `./scripts/start-wsl.sh` + Windows host script above |
| Linux | `./scripts/start-linux.sh` |
| macOS | `./scripts/start-macos.sh` |

Host prints:

```text
Session: <uuid>
PIN:     123456
```

## 3. Connect from browser

1. Open `http://127.0.0.1:8443` (or `https://` if you generated certs).
2. Paste **Session ID** and **PIN**.
3. Tap **Connect** — your desktop appears; touch = mouse.

## 4. Connect from phone (WireGuard)

1. Set up VPN: `infra/wireguard/README.md`
2. Connect WireGuard on the phone.
3. On laptop: signaling on `0.0.0.0:8443`, host running.
4. Phone browser: `http://10.8.0.20:8443` (laptop VPN IP).
5. Same session + PIN.

**WSL note:** use your **Windows** LAN/VPN IP for the UI if signaling runs on Windows; if signaling runs only in WSL, use WSL’s reachable IP or run signaling on Windows too.

## 5. systemd (optional, Linux/WSL)

```bash
systemctl --user start rohomieo-signaling
# host still on the machine with the display
```

## 6. Stop

- Ctrl+C in dev scripts, or `systemctl --user stop rohomieo-signaling`
- Windows: close the PowerShell windows

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Black screen | Host must run on OS with the display (Windows app, not WSL for Win desktop) |
| WebSocket failed | Check signaling is up; URL ends with `/ws` |
| Invalid PIN | Copy PIN from host terminal after host starts |
| Link error `lxdo` | Re-run `./setup.sh` or install apt packages from README |
