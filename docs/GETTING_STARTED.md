# Getting started — laptop and phone

Step-by-step guide for **WSL2 + Windows** (recommended) and how to connect from your phone.

For other platforms see [USAGE.md](USAGE.md). Architecture: [ARCHITECTURE.md](ARCHITECTURE.md).

---

## What runs where

| Component | Where | Why |
|-----------|--------|-----|
| **Host** (screen capture + input) | **Windows** | Captures your real desktop |
| **Signaling + web UI** | **Windows** (`0.0.0.0:8443`) | Phone on same Wi‑Fi uses your laptop LAN IP — **no WSL portproxy** |
| **Build** | **WSL** | Cross-compiles `.exe` + runtime DLLs (no Visual Studio) |

---

## Part 1 — One-time setup

### WSL

```bash
cd ~/rohomieo
git pull
./setup.sh --wsl
```

Enter **sudo** when `apt` asks.

### Windows binaries (from WSL — no Visual Studio)

```bash
cd ~/rohomieo
./scripts/build-windows-host.sh
./scripts/sync-windows-run.sh
```

This puts everything in `C:\Users\<you>\AppData\Local\rohomieo-run` (exes, `libunwind.dll`, `libc++.dll`, web, certs).

### Firewall (Windows Admin, once)

```powershell
cd \\wsl.localhost\Ubuntu\home\josep\rohomieo
powershell -ExecutionPolicy Bypass -File .\scripts\windows\enable-phone-access.ps1
```

Approve UAC. This opens **TCP 8443** for phones on the same Wi‑Fi. You do **not** need `wsl-bridge-portproxy.ps1` for same‑Wi‑Fi use.

---

## Part 2 — Every session

### Easiest (WSL)

```bash
cd ~/rohomieo
./setup.sh --start
```

This syncs to Windows and opens **run-bridge** (signaling first, then host).

### Or manually

```bash
./scripts/sync-windows-run.sh
```

```powershell
cd \\wsl.localhost\Ubuntu\home\josep\rohomieo
powershell -ExecutionPolicy Bypass -File .\scripts\windows\run-bridge.ps1
```

Two windows:

1. **Signaling** — must show `Rohomieo signaling on 0.0.0.0:8443` and stay open  
2. **Host** — **Session ID** and **PIN**

### Test on laptop

```
https://127.0.0.1:8443
```

Accept the certificate warning. Enter Session + PIN → **Connect**.

---

## Part 3 — Phone on same Wi‑Fi

1. `ipconfig` on Windows → **Wi‑Fi IPv4** (e.g. `192.168.1.223`).  
   Do **not** use `172.18.x.x` (WSL virtual adapter).

2. On phone (same Wi‑Fi):

   ```
   https://192.168.1.223:8443
   ```

   Use **https**, accept the certificate warning.

3. Same **Session ID** and **PIN** from the host window.

### If phone cannot connect

| Check | Action |
|-------|--------|
| Host shows `websocket connect refused` | Signaling not running — run `run-bridge.ps1` again |
| Missing DLL popup | Run `./scripts/sync-windows-run.sh` |
| Laptop `https://127.0.0.1:8443` works, phone does not | Run `enable-phone-access.ps1` as **Administrator** |
| Guest Wi‑Fi / AP isolation | Use main LAN or VPN (Part 4) |

---

## Part 4 — Phone away from home (WireGuard)

After Part 3 works on home Wi‑Fi.

See [infra/wireguard/wsl-bridge/README.md](../infra/wireguard/wsl-bridge/README.md) and [infra/wireguard/README.md](../infra/wireguard/README.md).

---

## Quick reference

| When | Command |
|------|---------|
| Build exes | `./scripts/build-windows-host.sh` |
| Sync to Windows | `./scripts/sync-windows-run.sh` |
| Start session | `./setup.sh --start` |
| Stop | `./setup.sh --stop` |
| Firewall once (Admin) | `scripts\windows\enable-phone-access.ps1` |
| Phone same Wi‑Fi | `https://<wifi-ipv4>:8443` |

---

## Troubleshooting

| Problem | What to do |
|---------|------------|
| `Code execution cannot proceed` (DLL) | `./scripts/sync-windows-run.sh` |
| Signaling exits immediately | Rebuild: `./scripts/build-windows-host.sh` |
| Host `connection refused` :8443 | Start signaling before host; use `run-bridge.ps1` |
| `link.exe not found` | Not needed — use `build-windows-host.sh` in WSL |
| Black video | Host must be **Windows** `.exe`, not WSL X11 host |

---

## iOS native app (optional)

```bash
cd mobile && flutter create . --platforms=ios && flutter pub get && flutter run -d ios
```

See [mobile/README.md](../mobile/README.md).
