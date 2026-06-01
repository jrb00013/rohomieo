# Rohomieo

Stream and control your computer from your phone over **WireGuard** + **WebRTC** — a self-hosted remote desktop stack you own.

## One-command setup

| Platform | Command |
|----------|---------|
| **Auto-detect** | `./setup.sh` |
| **WSL2** | `./setup.sh --wsl` |
| **Start session** | `./setup.sh --start` (Windows signaling + host, phone on LAN) |
| **Stop** | `./setup.sh --stop` |
| **Build Windows exes** | `./scripts/build-windows-host.sh` (no Visual Studio) |
| **Linux / macOS** | `./setup.sh --linux` / `--macos` |

```bash
git clone https://github.com/jrb00013/rohomieo.git ~/rohomieo
cd ~/rohomieo
./setup.sh              # or: --wsl | --linux | --macos
```

Shell scripts (`setup-*.sh`) complement **`scripts/setup-windows.ps1`** — Windows builds the `.exe` host for your real desktop; WSL/Linux/macOS scripts build Unix binaries + signaling.

## Run

| Platform | Start |
|----------|-------|
| WSL + Windows desktop | `./setup.sh --start` |
| Linux | `./scripts/start-linux.sh` |
| macOS | `./scripts/start-macos.sh` |
| Windows only | `powershell -File scripts\windows\run-bridge.ps1` |

```bash
source ~/rohomieo/.env.rohomieo
~/.local/bin/rohomieo-signaling   # or use start-*.sh above
~/.local/bin/rohomieo-host
```

Dev: `./scripts/dev.sh`

Open **https://127.0.0.1:8443** (or `https://<your-wifi-ip>:8443` on phone), accept the cert warning, enter **Session ID** + **PIN** from the host window.

**Full walkthrough (laptop + phone):** [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)

## WireGuard (phone off home Wi‑Fi)

[infra/wireguard/README.md](infra/wireguard/README.md)

## iOS app

```bash
cd mobile && flutter create . --platforms=ios && flutter pub get && flutter run -d ios
```

## Layout

```text
rohomieo/
  setup.sh                  # dispatcher: --linux | --wsl | --macos | --windows
  scripts/setup-linux.sh
  scripts/setup-wsl.sh
  scripts/setup-macos.sh
  scripts/setup-windows.ps1   # Windows host (built via WSL MinGW, no Visual Studio)
  scripts/start-{linux,wsl,macos}.sh
  crates/{proto,signaling,host}
  web/                  # PWA viewer
  mobile/               # Flutter iOS
```

## License

MIT — see [LICENSE](LICENSE)
