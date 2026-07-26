# Rohomieo Elevated Broker

LocalSystem Windows service that performs privileged Rohomieo ops without UAC spam.

## Pattern

1. **Once (UAC):** `scripts/windows/install-broker.ps1` installs `RohomieoBroker` under `LocalSystem`.
2. **Always:** unprivileged `rohomieo-broker-ctl.exe` talks to `\\.\pipe\RohomieoBroker`.

Same idea as Docker Desktop / SQL Server helpers: a first-party broker, not a UAC bypass.

## Commands

| Client | Effect |
|--------|--------|
| `PING` | Health check |
| `FIREWALL_ADD` / `FIREWALL_REMOVE` | TCP 8443 inbound rule |
| `DEFENDER_ADD <path>` / `DEFENDER_REMOVE <path>` | Path under `%LOCALAPPDATA%\rohomieo-run` only |
| `START_HOST` / `START_SIGNALING` | `CreateProcessAsUser` via `WTSQueryUserToken` |
| `STOP_HOST` / `STOP_SIGNALING` / `KILL_ALL` | `taskkill` |

## Build (WSL)

```bash
./scripts/build-windows-broker.sh
./scripts/sync-windows-run.sh
# Then once, elevated:
# powershell -File %LOCALAPPDATA%\rohomieo-run\install-broker.ps1
```

Or just `./install.sh` — it builds, stages, and prompts UAC once to install the service.

## Uninstall

```powershell
powershell -File scripts\windows\install-broker.ps1 -Uninstall
```

Log: `%ProgramData%\Rohomieo\broker.log`
