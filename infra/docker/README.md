# Docker

Build the signaling image from the repo root (requires `web/dist`):

```bash
make web-build
docker compose build
docker compose up
```

Signaling listens on **8443**. Mount your own TLS certs via compose overrides for production.

Host capture cannot run inside this container — run `rohomieo-host` on the machine with the display.
