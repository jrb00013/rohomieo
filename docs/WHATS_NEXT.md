# What's next for Rohomieo

A one-page deck for contributors and users.

---

## TL;DR

Rohomieo **works today** for same-Wi‑Fi and WireGuard remote desktop. v0.2 adds **observability, CI, and viewer polish**. v0.3 is **security** (device keys). v0.4 is **QoL** (clipboard, multi-monitor, WoL).

---

## You can use it now if…

| Scenario | Ready? |
|----------|--------|
| Phone on same Wi‑Fi as Windows laptop | ✅ `./setup.sh --start` |
| Phone on WireGuard VPN to home | ✅ See `infra/wireguard/` |
| Linux/macOS host | ✅ `./scripts/start-linux.sh` |
| iOS native app | 🟡 Flutter scaffold — browser PWA recommended |
| Untrusted public internet | ❌ Use VPN first |

---

## v0.2 shipped in this release

```
┌─────────────────────────────────────────────────────────┐
│  OBSERVABILITY                                          │
│  • /health  /metrics  /api/status  /api/audit           │
│  • Connection audit log (host join, viewer join, fail)  │
├─────────────────────────────────────────────────────────┤
│  RELIABILITY                                            │
│  • Stale session cleanup (TTL)                          │
│  • PIN brute-force rate limit                           │
├─────────────────────────────────────────────────────────┤
│  VIEWER                                                 │
│  • Remember session in localStorage                     │
│  • Fullscreen, scroll wheel, right-click                │
│  • PWA manifest + icons                                 │
├─────────────────────────────────────────────────────────┤
│  DEVOPS                                                 │
│  • GitHub Actions CI                                    │
│  • docker-compose.yml                                   │
│  • Makefile, health-check script                        │
└─────────────────────────────────────────────────────────┘
```

---

## Top 5 next engineering bets

| # | Bet | Why |
|---|-----|-----|
| 1 | **Ed25519 pairing** | PIN is fine for LAN; device keys scale to VPN + multi-device |
| 2 | **Host config file** | Stop retyping `--signaling` and FPS flags |
| 3 | **Clipboard sync** | #1 feature request for real work sessions |
| 4 | **Multi-monitor** | Laptops with dock + external display |
| 5 | **Android viewer** | Flutter code mostly shared with iOS |

---

## Metrics that matter

Track these once `/metrics` is scraped:

| Metric | Target |
|--------|--------|
| `rohomieo_sessions_active` | 0 when idle, 1 when you're connected |
| `rohomieo_pin_failures_total` | Should stay near 0 (typos only) |
| `rohomieo_ws_connections` | Signaling load |
| Time-to-first-frame | < 3s on LAN |

---

## Call to action

1. **Users:** Star the repo, file issues with your platform + steps.
2. **Contributors:** Grab Phase 1 leftovers or Phase 2 security — see [ROADMAP.md](ROADMAP.md).
3. **Operators:** Run `docker compose up` or wire Prometheus to `:8443/metrics`.

Full detail: [ROADMAP.md](ROADMAP.md) · Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
