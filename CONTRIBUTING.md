# Contributing to Rohomieo

Thanks for helping build self-hosted remote desktop tooling.

## Development setup

```bash
git clone https://github.com/jrb00013/rohomieo.git
cd rohomieo
./setup.sh          # or --wsl | --linux | --macos
make dev            # signaling + web dev servers
```

Requirements: Rust stable, Node 20+, platform libs from [README](README.md).

## Project layout

| Path | Purpose |
|------|---------|
| `crates/proto` | Shared JSON types — change here first for protocol work |
| `crates/signaling` | WebSocket server + static PWA |
| `crates/host` | Capture, encode, WebRTC, input |
| `web/` | React viewer |
| `mobile/` | Flutter iOS viewer |
| `scripts/` | Platform setup and bridge helpers |

## Making changes

1. **Branch** from `main`: `feat/short-description` or `fix/issue-N`
2. **Build** before pushing:
   ```bash
   make check        # cargo check + web tsc
   make test         # unit tests
   ```
3. **Commit messages** — conventional style:
   - `feat(signaling): add audit log endpoint`
   - `fix(web): wheel delta on trackpad`
   - `docs: update WireGuard guide`
4. **PR** — fill out the template; link issues if any.

## Protocol changes

1. Update `crates/proto/src/lib.rs`
2. Mirror in `web/src/proto.ts` and `mobile/lib/proto.dart`
3. Document in `proto/messages.md`
4. Bump minor version if wire-incompatible

## Testing

```bash
cargo test -p rohomieo-proto -p rohomieo-signaling
cd web && npm run build
./scripts/health-check.sh http://127.0.0.1:8443
```

Manual smoke test: start host + signaling, connect from browser with session/PIN.

## Code style

- Rust: `cargo fmt`, `cargo clippy -- -D warnings` (CI enforces)
- TypeScript: match existing React patterns in `web/src/`
- Keep diffs focused — one logical change per commit when possible

## Questions

Open a [Discussion](https://github.com/jrb00013/rohomieo/discussions) or issue. See [ROADMAP.md](docs/ROADMAP.md) for planned work.
