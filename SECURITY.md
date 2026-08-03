# Security policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.2.x   | ✅        |
| 0.1.x   | Best effort |

## Reporting a vulnerability

**Do not open public issues for security bugs.**

Email or DM the maintainer with:

- Description and impact
- Steps to reproduce
- Affected version / platform
- Suggested fix (optional)

We aim to acknowledge within 72 hours.

## Threat model (v0.2)

Rohomieo is designed primarily for **trusted networks** (home LAN or WireGuard VPN).  
`./scripts/run.sh --global` intentionally exposes a **short-lived session** to the public internet (UPnP and/or outbound tunnels). Treat that mode as higher risk.

| Control | Status |
|---------|--------|
| Media encryption | WebRTC SRTP (peer-to-peer or via TURN) |
| Signaling | TLS recommended; HTTPS/WSS via certs or Cloudflare tunnel |
| Authentication | Per-session PIN (8 digits in `--global`, 6 in `--local`); lockout after failed attempts |
| TURN credentials | Fresh per `--global` run (not reused from `.env`); embedded in the invite URL as a bearer secret |
| Admin telemetry | `/api/audit` and `/metrics` **off by default**; enable with `--expose-admin-api` (LAN) or `--admin-token` |
| Tunnel binaries | cloudflared / bore downloaded version-pinned with SHA-256 verification |
| Audit | Connection events logged server-side (export only when admin API enabled) |

**Trust boundaries for `--global`:**

- Anyone with the **join URL** (session + PIN + TURN secrets) can attempt to join as viewer.
- **UPnP** opens WAN ports to your PC while the session runs.
- **Quick tunnels** (trycloudflare.com / bore.pub) terminate TLS at a third party — operators can see signaling metadata; media remains SRTP end-to-end when peers connect.
- Stopping the session (Ctrl+C) tears down tunnels / best-effort UPnP cleanup; restart to rotate secrets.

**Not in scope for v0.2:** protection against a malicious signaling server you do not control, or device-bound viewer identity (planned: Ed25519 pairing).

## Best practices

1. Prefer `--local` or WireGuard when possible; use `--global` only while you need off-LAN access.
2. Treat the printed join URL / QR as a **password** — do not post it in public chats or screenshots.
3. Use TLS (`--cert` / `--key`) or the Cloudflare tunnel HTTPS front; accept cert warnings only for your own LAN IP.
4. Keep `/api/audit` and `/metrics` disabled on public sessions; for LAN ops use `--expose-admin-api` or a Bearer admin token.
5. Rotate access by stopping and restarting the host session (new PIN + TURN creds each `--global` run).
6. Keep WireGuard keys private; use separate phone/laptop keys.
7. Do not commit `.env.rohomieo*` files (gitignored).

## Planned improvements

See [ROADMAP.md](docs/ROADMAP.md) Phase 2: Ed25519 device pairing, signed tokens, mTLS.
