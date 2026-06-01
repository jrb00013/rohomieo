# Rohomieo

Stream and control your computer from your phone over **WireGuard** + **WebRTC** — a self-hosted remote desktop stack you own.

## One-command setup

| Platform | Command |
|----------|---------|
| **Auto-detect** | `./setup.sh` |
| **WSL2** | `./setup.sh --wsl` |
| **Install + start** | `./setup.sh --wsl --start` |
| **Start only** | `./setup.sh --start` |
| **Stop** | `./setup.sh --stop` |
| **Linux / macOS** | `./setup.sh --linux` / `--macos` |
| **Windows** | `powershell -File scripts\setup-windows.ps1` |

```bash
git clone https://github.com/jrb00013/rohomieo.git ~/rohomieo
cd ~/rohomieo
./setup.sh              # or: --wsl | --linux | --macos
```

Shell scripts (`setup-*.sh`) complement **`scripts/setup-windows.ps1`** — Windows builds the `.exe` host for your real desktop; WSL/Linux/macOS scripts build Unix binaries + signaling.

## Run

| Platform | Start |
|----------|-------|
| Linux | `./scripts/start-linux.sh` |
| WSL | `./scripts/start-wsl.sh` + `scripts\start-windows-host.ps1` on Windows |
| macOS | `./scripts/start-macos.sh` |
| Windows | `powershell -File scripts\start-windows-host.ps1` |

```bash
source ~/rohomieo/.env.rohomieo
~/.local/bin/rohomieo-signaling   # or use start-*.sh above
~/.local/bin/rohomieo-host
```

Dev: `./scripts/dev.sh`

Open **http://127.0.0.1:8443** (or your VPN IP), enter **Session ID** + **PIN** from the host log.

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
