# Rohomieo roadmap

Where we are, where we're going, and how to contribute.

**Status:** v0.2.0 — production-usable LAN + WireGuard remote desktop  
**Last updated:** June 2026

---

## Vision

Rohomieo is a **self-hosted remote desktop you own**: no SaaS account, no per-minute billing, no third-party relay for media. WireGuard gets your phone onto your laptop's network; WebRTC carries encrypted video peer-to-peer.

The north star: **open a phone browser, tap Connect, and you're at your desk** — with latency and quality that feel native, on hardware you already have.

---

## Shipped (v0.1 → v0.2)

| Area | What |
|------|------|
| **Core** | Host capture (DXGI/X11/Quartz), H.264 + JPEG fallback, WebRTC data channel input |
| **Signaling** | Axum WebSocket relay, TLS, static PWA hosting |
| **Adaptive stream** | Motion-aware FPS (idle ~8 FPS, motion up to 30) |
| **Platforms** | Windows host via MinGW/WSL, Linux, macOS, WSL2 LAN bridge |
| **Viewers** | React PWA, Flutter iOS scaffold |
| **VPN** | WireGuard examples + WSL mirrored networking bridge |
| **Ops** | `setup.sh --start/--stop`, health endpoint, connection audit log (v0.2) |

---

## Phase 1 — Polish & trust (v0.2, **now**)

Goal: make daily use frictionless and observable.

- [x] Connection audit log (signaling)
- [x] Prometheus-style `/metrics`
- [x] JSON `/api/status` for monitoring
- [x] Session TTL cleanup for stale registrations
- [x] PIN attempt rate limiting
- [x] PWA install prompts + session persistence in browser
- [x] Fullscreen viewer, scroll wheel, right-click
- [x] CI (Rust + web build)
- [x] Docker Compose for signaling + dev stack
- [x] Host config file (`~/.config/rohomieo/host.toml`)
- [ ] Connection quality overlay (RTT, FPS estimate)

---

## Phase 2 — Security hardening (v0.3)

Goal: replace shared PIN with device identity and auditability.

| Item | Description |
|------|-------------|
| **Ed25519 device keys** | Host generates keypair; viewer pairs once, stores public key |
| **Signed session tokens** | Short-lived JWT instead of raw PIN over signaling |
| **Connection audit export** | JSON/CSV download from `/api/audit` |
| **mTLS signaling** | Optional client certs on WireGuard-only bind |
| **PIN rotation** | Host rotates PIN every N minutes or on disconnect |
| **Fail2ban-style lockout** | Escalating backoff after bad PINs |

Scripts stubbed in `scripts/gen-device-key.sh` — full integration in 0.3.

---

## Phase 3 — Quality of life (v0.4)

| Item | Description |
|------|-------------|
| **Multi-monitor** | Host flag `--display 1`; viewer monitor switcher |
| **Clipboard sync** | Text bidirectional over data channel |
| **Audio forward** | Opus track (optional, off by default) |
| **Wake-on-LAN** | `scripts/wake-on-lan.sh` + host registers MAC in config |
| **Android viewer** | Flutter `android` target |
| **File drop** | Drag file onto viewer → save on host |

---

## Phase 4 — Scale & ecosystem (v0.5+)

| Item | Description |
|------|-------------|
| **TURN on LAN only** | Optional coturn in Docker for symmetric NAT edge cases |
| **Multi-viewer** | Read-only guests vs one control viewer |
| **Session recording** | Encrypted local dump for support/debug |
| **Grafana dashboard** | Import `infra/grafana/rohomieo.json` |
| **Home Assistant** | Binary sensor "desk online" via `/api/status` |
| **Nix flake** | Reproducible dev + deploy |

---

## Non-goals (for now)

- Public internet without VPN (we are not a cloud RDP service)
- macOS/iOS host capture (viewer only on Apple mobile)
- Game streaming / sub-20ms competitive latency
- Replacing TeamViewer's NAT traversal for strangers

---

## How to pick up work

1. Read [WHATS_NEXT.md](WHATS_NEXT.md) for the executive summary.
2. Check [open issues](https://github.com/jrb00013/rohomieo/issues) or pick an unchecked box above.
3. See [CONTRIBUTING.md](../CONTRIBUTING.md) for build/test workflow.

**Good first issues:** web UI polish, docs, WireGuard guides, Flutter viewer, audit log filters.

## Version history

See [CHANGELOG.md](../CHANGELOG.md).
