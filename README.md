# Rohomieo

Stream and control your computer from your phone over **WireGuard** + **WebRTC** — a self-hosted remote desktop stack you own.

## One-command setup

| Platform | Command |
|----------|---------|
| **Install + start** | `./install.sh` (deps, build, broker/UAC once, start) |
| **Legacy setup** | `./setup.sh` / `./setup.sh --wsl` |
| **Start session** | `./install.sh` again, or `./setup.sh --start` |
| **Stop** | `./setup.sh --stop` |
| **Build Windows exes** | `./scripts/build-windows-host.sh` (no Visual Studio) |

```bash
git clone https://github.com/jrb00013/rohomieo.git ~/rohomieo
cd ~/rohomieo
./install.sh            # approve UAC once to install RohomieoBroker; later installs are silent
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

Open **https://127.0.0.1:8443** (or scan the **QR code** in the host window — opens the phone browser and joins the session), accept the cert warning. Manual connect: enter **Session ID** + **PIN** from the host window.

**Full walkthrough (laptop + phone):** [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)

**Roadmap & what's next:** [docs/WHATS_NEXT.md](docs/WHATS_NEXT.md) · [docs/ROADMAP.md](docs/ROADMAP.md)

## WireGuard (phone off home Wi‑Fi)

[infra/wireguard/README.md](infra/wireguard/README.md)

## iOS app

```bash
cd mobile && flutter create . --platforms=ios && flutter pub get && flutter run -d ios
```

## Layout

```text
rohomieo/
  install.sh                # one-shot: deps, build, broker (UAC once), start
  setup.sh                  # dispatcher: --linux | --wsl | --macos | --windows
  Makefile                  # check, test, web-build
  docker-compose.yml        # signaling container
  docs/ROADMAP.md           # phased feature plan
  scripts/setup-linux.sh
  scripts/setup-wsl.sh
  scripts/setup-macos.sh
  scripts/setup-windows.ps1   # Windows host (built via WSL MinGW, no Visual Studio)
  scripts/windows/install-broker.ps1  # UAC once: LocalSystem elevated broker service
  scripts/windows/install-allow.ps1   # fallback elevated allow (firewall/SAC/sign)
  native/rohomieo-broker/   # C++ LocalSystem broker + ctl (named pipe)
  scripts/start-{linux,wsl,macos}.sh
  crates/{proto,signaling,host}
  web/                  # PWA viewer
  mobile/               # Flutter iOS
```

## License

MIT — see [LICENSE](LICENSE)
