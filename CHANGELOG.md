# Changelog

All notable changes to Rohomieo are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Planned
- Host config file auto-discovery at `~/.config/rohomieo/host.toml`
- Connection quality overlay in web viewer

## [0.2.0] - 2026-06-22

### Added

- Comprehensive [ROADMAP.md](docs/ROADMAP.md) and [WHATS_NEXT.md](docs/WHATS_NEXT.md)
- Signaling connection audit log with `/api/audit` endpoint
- Prometheus-style `/metrics` and JSON `/api/status`
- Session TTL cleanup for abandoned registrations
- PIN attempt rate limiting per session
- `--version` flags on host and signaling binaries
- Host TOML config file support (`--config`)
- GitHub Actions CI (Rust check, clippy, web build)
- Docker Compose stack for signaling + dev
- Makefile with common dev targets
- PWA icons and improved viewer UX (fullscreen, wheel, right-click)
- Session persistence in browser localStorage
- `scripts/health-check.sh`, `scripts/gen-device-key.sh`, `scripts/wake-on-lan.sh`
- CONTRIBUTING.md, SECURITY.md, `.env.example`
- GitHub issue and PR templates

### Changed

- Health endpoint returns structured JSON at `/api/status`
- README links to roadmap and what's next docs
- Workspace version bumped to 0.2.0

## [0.1.0] - 2026-06

### Added

- Initial release: host, signaling, web PWA, Flutter iOS scaffold
- WireGuard VPN examples and WSL2 LAN bridge
- Windows cross-compile via llvm-mingw (no Visual Studio)
- `setup.sh` with `--start` / `--stop` for one-command sessions
- Adaptive motion-based FPS throttling
- JPEG datachannel fallback for mobile browsers
- TLS signaling with dev cert generation

[Unreleased]: https://github.com/jrb00013/rohomieo/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/jrb00013/rohomieo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jrb00013/rohomieo/releases/tag/v0.1.0
