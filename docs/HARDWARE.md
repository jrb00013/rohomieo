# Hardware

Compatible hardware for use with Rohomieo remote desktop sessions.

## Smart Plugs — Kasa EP10P4

**Purchased:** September 2026

| Detail | Value |
|--------|-------|
| **Model** | TP-Link Kasa Smart Plug Ultra Mini 15A |
| **SKU** | EP10P4 |
| **Quantity** | 4-pack |
| **Rating** | 15A / 120V / 1800W |
| **Wireless** | 2.4 GHz Wi-Fi only |
| **Voice assistants** | Alexa, Google Home |
| **Hub required** | No |
| **Certification** | UP Certified, UL Listed |
| **Local API** | Yes — `python-kasa` (LAN, no cloud) |

### Why this plug

- **Local LAN control** via [python-kasa](https://github.com/python-kasa/python-kasa) — script and automate from the host desktop without cloud dependency.
- **Compact form factor** — Ultra Mini design doesn't block adjacent outlets.
- **15A rating** — handles lamps, fans, monitors, chargers, and most household appliances.
- **No hub required** — connects directly to existing Wi-Fi.
- Works inside a Rohomieo session: remote into your desktop, run `kasa` CLI or Python scripts to toggle outlets from your phone.

### Quick start — python-kasa

```bash
pip install python-kasa

# discover plugs on LAN
kasa discover

# turn on plug alias "desk-lamp"
kasa --alias desk-lamp on

# turn off
kasa --alias desk-lamp off

# get current state
kasa --alias desk-lamp state
```

### Python example — toggle from Rohomieo session

```python
import asyncio
from kasa import Discover

async def main():
    devices = await Discover.discover()
    for addr, dev in devices.items():
        await dev.update()
        print(f"{dev.alias} ({addr}): {'ON' if dev.is_on else 'OFF'}")

asyncio.run(main())
```

### Integration roadmap

Planned Rohomieo features that connect to smart plugs:

| Phase | Feature | Status |
|-------|---------|--------|
| Phase 4 | Home Assistant binary sensor (`/api/status`) | Planned |
| — | python-kasa CLI scripts on host | Works today |

### Tips

- Use `--global` mode to toggle plugs from outside your home network.
- Assign static DHCP leases so plug IPs don't change.
- Group plugs by room in the Kasa app for easier scripting by alias name.
