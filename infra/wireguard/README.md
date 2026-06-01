# WireGuard setup for Rohomieo

Rohomieo is designed **fail-closed**: signaling and WebRTC run on your VPN (`10.8.0.0/24`). Do not port-forward `8443` to the public internet unless you add extra hardening.

## Topology

```text
                    [Internet]
                         |
                   UDP 51820 (WG)
                         |
              +----------+----------+
              |  VPN server (Pi)   |
              |  10.8.0.1          |
              +----------+----------+
                    /         \
            10.8.0.20       10.8.0.30
           [Laptop]         [Phone]
        host + signaling   PWA / iOS app
```

## 1. Generate keys (once per device)

**Automatic (during `./setup.sh`):** keys are created under `infra/wireguard/keys/` if missing.

**Manual:**

```bash
./scripts/wireguard-gen-keys.sh
# or:
umask 077
wg genkey | tee server.key | wg pubkey > server.pub
```

## 2. Server (`wg0`) — Raspberry Pi / home server

See [server.conf.example](server.conf.example). Enable forwarding:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
# persist in /etc/sysctl.conf
```

```bash
sudo cp server.conf /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

## 3. Laptop peer

See [laptop.conf.example](laptop.conf.example). After VPN is up:

```bash
cargo run -p rohomieo-signaling -- --bind 0.0.0.0:8443
cargo run -p rohomieo-host -- --signaling ws://127.0.0.1:8443/ws
```

Open from phone: `https://10.8.0.20:8443` (with TLS cert) or `http://10.8.0.20:8443` on trusted VPN only.

## 4. Phone peer

Import [phone.conf.example](phone.conf.example) into the WireGuard iOS/Android app. Connect before opening Rohomieo.

## 5. TLS for signaling (recommended)

```bash
./scripts/gen-dev-cert.sh
cargo run -p rohomieo-signaling -- \
  --bind 0.0.0.0:8443 \
  --cert infra/certs/cert.pem \
  --key infra/certs/key.pem
```

Trust the cert on your phone (Settings → General → About → Certificate Trust Settings) or use a LAN CA.

## Checklist

- [ ] VPN connects from cellular with Wi‑Fi off
- [ ] `curl -k https://10.8.0.20:8443/health` returns `ok`
- [ ] Host prints session ID + PIN
- [ ] Viewer connects and shows desktop
- [ ] Touch/mouse moves cursor on host
