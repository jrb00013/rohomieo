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

Rohomieo is designed for **trusted networks** (home LAN or WireGuard VPN):

| Control | Status |
|---------|--------|
| Media encryption | WebRTC SRTP (peer-to-peer) |
| Signaling | TLS recommended; optional HTTP on VPN only |
| Authentication | 6-digit PIN per session (v0.2); device keys planned v0.3 |
| Audit | Connection events logged server-side |
| Rate limiting | PIN failures throttled per session |

**Not in scope for v0.2:** protection against a malicious signaling server operator (use your own server), or exposure to the public internet without VPN.

## Best practices

1. Run signaling bound to WireGuard IP or LAN — not `0.0.0.0` on untrusted networks without firewall.
2. Use TLS (`--cert` / `--key`) when browsers connect over HTTPS.
3. Rotate PINs by restarting the host session.
4. Review `/api/audit` for unexpected viewer joins.
5. Keep WireGuard keys private; use separate phone/laptop keys.

## Planned improvements

See [ROADMAP.md](docs/ROADMAP.md) Phase 2: Ed25519 device pairing, signed tokens, mTLS.
