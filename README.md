# Rohomieo

Stream and control your computer from your phone over **WireGuard** + **WebRTC** — a self-hosted remote desktop stack you own.

## One-command setup

**WSL or Linux:**

```bash
git clone https://github.com/jrb00013/rohomieo.git ~/rohomieo
cd ~/rohomieo
./setup.sh
```

**Windows (PowerShell as your user):**

```powershell
git clone https://github.com/jrb00013/rohomieo.git $env:USERPROFILE\rohomieo
cd $env:USERPROFILE\rohomieo
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
```

**WSL + Windows desktop (recommended on WSL2):** run `./setup.sh` in WSL (signaling + web), then let it invoke Windows setup for the **host** that captures your real desktop.

## Run

```bash
source ~/rohomieo/.env.rohomieo
~/.local/bin/rohomieo-signaling   # terminal 1
~/.local/bin/rohomieo-host        # terminal 2 (on the machine with the display)
```

Or quick dev: `./scripts/dev.sh`

Open **http://127.0.0.1:8443** (or your VPN IP), enter **Session ID** + **PIN** from the host log.

## WireGuard (phone off home Wi‑Fi)

[infra/wireguard/README.md](infra/wireguard/README.md)

## iOS app

```bash
cd mobile && flutter create . --platforms=ios && flutter pub get && flutter run -d ios
```

## Layout

```text
rohomieo/
  setup.sh              # WSL/Linux installer
  scripts/setup-windows.ps1
  crates/{proto,signaling,host}
  web/                  # PWA viewer
  mobile/               # Flutter iOS
```

## License

MIT — see [LICENSE](LICENSE)
