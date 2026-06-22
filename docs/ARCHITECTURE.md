# Rohomieo architecture

Self-hosted remote desktop: **host agent** streams the display over **WebRTC**; **viewers** (PWA, Flutter iOS) send input on a **DataChannel**. **Signaling** only exchanges SDP/ICE; media stays peer-to-peer on the WireGuard LAN.

## Components

| Crate / dir | Role |
|-------------|------|
| `crates/proto` | JSON types (signaling + input) |
| `crates/signaling` | Axum WebSocket + static PWA |
| `crates/host` | scrap capture, OpenH264, webrtc-rs, enigo input |
| `web/` | React PWA viewer |
| `mobile/` | Flutter iOS viewer |
| `infra/wireguard/` | VPN examples |

## Connection flow

1. Host registers `register_host` with `session_id` + `pin`.
2. Viewer registers `register_viewer` with same credentials.
3. Server sends `peer_joined` to host.
4. Host creates WebRTC **offer** (H.264 video + `input` data channel).
5. Viewer **answer** + ICE candidates via signaling relay.
6. Encrypted SRTP video flows directly over VPN IPs.

## Adaptive streaming

- **WebRTC GCC** — congestion control on the video track.
- **Motion detector** (`crates/host/src/motion.rs`) — tile diff; skips encode when &lt;2% pixels change; idle ~8 FPS, motion up to `--fps` (default 30).

## Platform notes

| OS | Capture | Input |
|----|---------|-------|
| Windows | DXGI via `scrap` | `enigo` |
| Linux | X11 via `scrap` | `enigo` + libxdo |
| macOS | Quartz via `scrap` | `enigo` + Screen Recording permission |

Build deps (Linux): `libx11-dev libxcb1-dev libxcb-shm0-dev libxcb-randr0-dev libxdo-dev`

## Security (v1)

- 6-digit PIN per session
- PIN attempt rate limiting and 5-minute lockout (v0.2)
- Connection audit log at `/api/audit` (v0.2)
- No STUN/TURN on public internet (VPN required)
- Optional TLS on signaling (`--cert` / `--key`)

Future: Ed25519 device keys, signed session tokens, Wake-on-LAN — see [ROADMAP.md](ROADMAP.md).

## Observability (v0.2)

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Plain-text liveness |
| `GET /api/status` | JSON version + session counts |
| `GET /api/audit` | Recent connection events |
| `GET /metrics` | Prometheus scrape target |
