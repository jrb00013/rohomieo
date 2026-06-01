# WSL2 WireGuard bridge

Run the **VPN server inside WSL** (`10.8.0.1`) and expose it to your phone via Windows networking — one laptop, no Raspberry Pi.

```text
                    [Internet / router UDP 51820]
                              |
                    [Windows 11 + mirrored WSL]
                              |
              +---------------+---------------+
              |  WSL: wg0 10.8.0.1            |
              |  signaling :8443              |
              +---------------+---------------+
                              |
              [Windows: rohomieo-host.exe]  <- desktop capture
                              |
                    [Phone 10.8.0.30 on VPN]
                    http://10.8.0.1:8443
```

## Why mirrored networking?

Classic WSL2 uses a virtual NAT. **UDP port 51820** cannot be forwarded to WSL with `netsh portproxy` (TCP only).  
**Fix:** enable `networkingMode=mirrored` in `%USERPROFILE%\.wslconfig` so WSL shares Windows network adapters.

## One-time setup

### 1. WSL packages + keys

```bash
cd ~/rohomieo
./setup.sh --wsl
./scripts/wireguard-gen-keys.sh   # if keys/ is empty
```

### 2. Windows — mirrored networking (PowerShell)

```powershell
cd \\wsl.localhost\Ubuntu\home\josep\rohomieo
powershell -File scripts\windows\wsl-enable-mirrored-network.ps1
wsl --shutdown
wsl
```

### 3. WSL — install WireGuard config

```bash
./scripts/wireguard-wsl-bridge.sh install
```

### 4. Windows — firewall + TCP bridge (Admin PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\wsl-bridge-portproxy.ps1
```

Router: forward **UDP 51820** → your laptop’s LAN IP.

## Every session

**WSL:**

```bash
./scripts/start-wsl-bridge.sh
# or manually:
./scripts/wireguard-wsl-bridge.sh up
source .env.rohomieo && .local/bin/rohomieo-signaling
```

**Windows (desktop host):**

```powershell
powershell -File scripts\start-windows-host.ps1
```

**Phone:**

1. Import config: `./scripts/wireguard-wsl-bridge.sh phone-config`
2. Connect WireGuard
3. Browser: `http://10.8.0.1:8443` — session ID + PIN from **Windows** host window

## Commands

| Command | Purpose |
|---------|---------|
| `./scripts/wireguard-wsl-bridge.sh up` | Start `wg0` |
| `./scripts/wireguard-wsl-bridge.sh down` | Stop `wg0` |
| `./scripts/wireguard-wsl-bridge.sh status` | Show peers |
| `./scripts/wireguard-wsl-bridge.sh phone-config` | Print phone `.conf` |
| `./scripts/start-wsl-bridge.sh` | wg + signaling together |

## WebRTC note

- **Signaling** runs in WSL (`10.8.0.1:8443`) — phone reaches it over VPN.
- **Video/host** runs on **Windows** — WebRTC may use your Windows LAN/VPN route. If video fails over VPN but works on same Wi‑Fi, allow **Windows Firewall** for `rohomieo-host.exe` from `10.8.0.0/24`.

## Fallback: WireGuard on Windows only

If mirrored mode is unavailable (older Windows 10), use the GUI app instead:

```powershell
powershell -File scripts\setup-windows.ps1
# Import infra/wireguard/server.conf.example (edited with your keys) in WireGuard for Windows
```

See [../README.md](../README.md).
