# Getting started — laptop and phone

Step-by-step guide for **WSL2 + Windows** (recommended) and how to connect from your phone.

For other platforms see [USAGE.md](USAGE.md). Architecture: [ARCHITECTURE.md](ARCHITECTURE.md).

---

## What runs where

| Component | Where | Why |
|-----------|--------|-----|
| **Host** (screen capture + mouse/keyboard) | **Windows** | Captures your real desktop (including WSL terminals on screen) |
| **Signaling + web UI** | **Windows** (via `start-windows-host.ps1`) | Serves `http://…:8443` and WebSocket for the phone |
| **WSL setup** | Ubuntu in WSL | Builds tools; optional signaling-only — day-to-day use Windows scripts |

---

## Part 1 — One-time setup (laptop)

### Step 1 — WSL (Ubuntu terminal)

```bash
cd ~/rohomieo
git pull
./setup.sh --wsl
```

Enter your **sudo** password when `apt` runs.

If Windows setup fails at the end of this script, continue to Step 2 (Build Tools are required on Windows).

### Step 2 — Windows (PowerShell, not WSL)

1. Install **Visual Studio Build Tools**:  
   https://visualstudio.microsoft.com/visual-cpp-build-tools/

   - Select workload **“Desktop development with C++”**
   - Install and restart if prompted

2. Open **PowerShell** and run:

```powershell
cd \\wsl.localhost\Ubuntu\home\josep\rohomieo
powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1
```

Wait until the build finishes with **no** `link.exe not found` errors.

You should have:

- `target\release\rohomieo-host.exe`
- `target\release\rohomieo-signaling.exe`
- `web\dist\` (PWA)
- **WireGuard** (installed by `./setup.sh` — Windows app + `wg` in WSL for keys)
- Optional: `infra/wireguard/keys/*.key` generated on first setup

---

## Part 2 — Every time you use Rohomieo

### On the laptop (Windows)

```powershell
cd \\wsl.localhost\Ubuntu\home\josep\rohomieo
powershell -File .\scripts\start-windows-host.ps1
```

Two PowerShell windows open:

1. **Signaling** — web UI + WebSocket  
2. **Host** — prints **Session ID** and **PIN**

Copy both from the **host** window. Leave both windows open.

### Test on the laptop first

On the same PC, open a browser:

```
http://127.0.0.1:8443
```

Enter **Session ID** and **PIN** → **Connect**. You should see your desktop and be able to control it.

---

## Part 3 — Phone on the same Wi‑Fi

1. Find the laptop’s Wi‑Fi IP on Windows:

   ```powershell
   ipconfig
   ```

   Use **IPv4 Address** under your Wi‑Fi adapter (e.g. `192.168.1.42`).

2. On your phone (connected to the **same** Wi‑Fi), open Safari/Chrome:

   ```
   http://192.168.1.42:8443
   ```

   Replace with your actual IP.

3. Enter the same **Session ID** and **PIN** from the host window.

4. Tap **Connect**. Touch the screen to move the mouse; use **Keyboard** in the toolbar to type.

### If the phone cannot connect

- Confirm both devices are on the same Wi‑Fi (not guest network isolation).
- **Windows Firewall**: allow inbound **TCP 8443** on Private networks, or allow `rohomieo-signaling.exe` when prompted.
- Try `http://127.0.0.1:8443` on the laptop again — if that fails, fix Windows setup before debugging the phone.

---

## Part 4 — Phone away from home (WireGuard)

Do this **only after** Part 3 works on your home Wi‑Fi.

### Option A — WSL2 WireGuard bridge (VPN server in WSL)

Full guide: [infra/wireguard/wsl-bridge/README.md](../infra/wireguard/wsl-bridge/README.md)

```powershell
# Windows once — mirrored networking
powershell -File scripts\windows\wsl-enable-mirrored-network.ps1
wsl --shutdown
```

```bash
# WSL once
./scripts/wireguard-wsl-bridge.sh install
```

```powershell
# Windows Admin once — firewall + TCP 8443 to WSL
powershell -File scripts\windows\wsl-bridge-portproxy.ps1
```

**Each session (one command):**

```bash
./setup.sh --start
```

Or separately: `./scripts/start-wsl-bridge.sh` (foreground) + Windows `scripts\windows\start-host.ps1`

Stop: `./setup.sh --stop`

Phone: WireGuard on → `http://10.8.0.1:8443` → session + PIN.

### Option B — WireGuard on Windows only

See [../infra/wireguard/README.md](../infra/wireguard/README.md) — use WireGuard for Windows GUI instead of the WSL bridge.

---

## Quick reference

| When | Laptop | Phone |
|------|--------|--------|
| **Setup once (WSL)** | `./setup.sh --wsl` | — |
| **Setup once (Windows)** | `scripts\setup-windows.ps1` | — |
| **Each session** | `scripts\start-windows-host.ps1` | — |
| **Same Wi‑Fi** | `http://127.0.0.1:8443` (test) | `http://<laptop-lan-ip>:8443` |
| **On VPN** | host + signaling running | `http://10.8.0.1:8443` + WireGuard on |

---

## Other platforms

| Platform | Setup | Start |
|----------|--------|--------|
| Native Linux | `./setup.sh --linux` | `./scripts/start-linux.sh` |
| macOS | `./setup.sh --macos` | `./scripts/start-macos.sh` |
| WSL signaling only | `./setup.sh --wsl` | `./scripts/start-wsl.sh` (+ Windows host for desktop) |

---

## Troubleshooting

| Problem | What to do |
|---------|------------|
| `link.exe not found` on Windows | Install Visual Studio Build Tools (C++ workload), re-run `setup-windows.ps1` |
| Black or empty video | Host must run on **Windows**, not only in WSL |
| `invalid PIN` | Use PIN from the host window **after** it started this session |
| WebSocket error | URL must end with `/ws` in the app; signaling window must stay open |
| WSL `lxcb` / `lxdo` link errors | `sudo apt install libx11-dev libxcb1-dev libxdo-dev` then re-run setup |
| apt `nodejs Conflicts: npm` | You already have Node (e.g. NodeSource). Re-run `./setup.sh --wsl` — script skips apt node packages when `node`/`npm` work |

---

## iOS native app (optional)

```bash
cd mobile
flutter create . --platforms=ios
flutter pub get
flutter run -d ios
```

Connect WireGuard first, then use the same signaling URL and PIN. See [mobile/README.md](../mobile/README.md).
