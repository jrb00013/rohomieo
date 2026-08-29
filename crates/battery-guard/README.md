# rohomieo-battery-guard

Caps battery charge on a laptop running rohomieo as an always-on host, so
it doesn't sit at 100% charge indefinitely while plugged in.

## Usage

    rohomieo-battery-guard --detect          # print detected vendor/model only
    rohomieo-battery-guard --status          # print current charge/limit state
    rohomieo-battery-guard                   # detect vendor, apply 80% limit if supported
    rohomieo-battery-guard --limit 60        # apply a custom limit

Debug logs: `RUST_LOG=rohomieo_battery_guard=debug rohomieo-battery-guard`

## Vendor support

| Vendor | Auto-applies | Notes |
|--------|---------------|-------|
| ASUS   | Yes | Verified on ROG Strix G18 — see mechanism below |
| Lenovo | No (print-only) | WMI method implemented, not yet hardware-verified |
| Dell   | No (print-only) | WMI method implemented, not yet hardware-verified |
| HP     | No (print-only) | WMI method implemented, not yet hardware-verified |

Vendors marked "print-only" detect correctly and print the exact WMI call
that would be made (`--limit` still resolves and is shown), but do not
invoke it. Once someone verifies a vendor's method against real hardware,
flip it to auto-apply in `src/vendor/mod.rs::limiter_for` by changing
nothing but that vendor's `auto_applies()` — the call logic is already
implemented and unit-tested against a mock WMI transport.

### ASUS mechanism (why it isn't raw WMI)

ASUS's ATK WMI interface for battery control is real and callable
(`root\wmi` class `AsusAtkWmi_WMNB`, methods `DEVS`/`DSTS`, device ID
`0x00120057` — the same interface and DevID Linux's `asus-wmi` kernel
driver uses), but on the ROG Strix G18 its ACPI-WMI security descriptor
rejects every caller except Armoury Crate's own SYSTEM service. This was
confirmed by hitting an identical `WBEM_E_INVALID_PARAMETER` from three
independent, fully-elevated invocation paths (raw COM `IWbemServices`,
legacy `.NET`/`System.Management`, and the modern CIM cmdlets) — even for
the simplest possible call (`INIT` with a single zero argument). That
consistent failure across unrelated stacks means it isn't a parameter or
binding bug; it's an intentional access restriction.

Rather than escalate to raw EC port I/O to route around that (see the
section below — real risk of hardware damage), `AsusLimiter` drives the
exact mechanism Armoury Crate's own `ASUSOptimization` service already
uses: a plain, world-writable INI file it polls —
`C:\ProgramData\ASUS\ASUS System Control Interface\AsusOptimization\Customization.ini`,
section `[BatteryHealthCharging]`, key `value=<percent>` — applied by
restarting that service (`sc.exe stop`/`start ASUSOptimization`). This is
the real electrical charge-cutoff mechanism (the embedded controller
genuinely stops delivering charge current at the target percentage, the
same as unplugging for charging purposes while AC still powers the
machine) — it's Armoury Crate's own documented behavior, just applied
without needing its GUI running. Both the file path and the service
restart are overridable via `ROHOMIEO_BATTERY_GUARD_ASUS_INI` and
`ROHOMIEO_BATTERY_GUARD_SKIP_SERVICE_RESTART` for testing.

## If a vendor's WMI method doesn't work

Some laptops don't expose a charge-threshold WMI method at all, or expose
one with different method/argument names than documented here. The next
level down is talking to the embedded controller (EC) directly via port
I/O (0x62/0x66 command/data ports) — this is what a charge-limit setting
ultimately resolves to in firmware. That path is **not implemented** in
this crate because it requires:

- A signed kernel-mode driver (WMI methods run in user mode; raw EC I/O
  does not).
- Reverse-engineered EC command bytes specific to that laptop's firmware
  revision — there's no vendor documentation for this layer.
- Real risk: sending the wrong EC command can desync the EC state machine
  or, in the worst case, damage charge-controller hardware.

If you hit this wall, the reference implementations to study are the
Linux kernel's `ideapad_laptop`/`thinkpad_acpi`/`asus-wmi` drivers (they
show the real EC command sequences for many vendors) and projects like
LenovoLegionToolkit or NBFC, which do exactly this style of EC access on
Windows. Treat it as a separate, much higher-risk project — not an
extension of this crate.

## Investigated and rejected: forcing the system off AC while plugged in

A charge *limit* (what this crate does) is not the same thing as forcing
the system to run off battery while AC stays physically connected — that
was explored for this crate and explicitly rejected. Recording why, so it
isn't re-attempted:

**Why it can't be done from software alone.** ACPI's `_PSR` (Power
Source) method is a one-way report: the EC reads its own hardware
AC-detect pin, writes that status into EC RAM, and `_PSR` just reads that
RAM value back to the OS. Data flows **EC → ACPI table → OS**, never the
reverse. The EC's actual charge/discharge decision is made entirely in EC
firmware from its own hardware pin state — it does not consult what the
OS's ACPI namespace reports. Overriding `_PSR` to always report "Offline"
(via a patched DSDT/SSDT — the only real mechanism for this, and one that
requires a reboot with a correctly recompiled AML table, not anything
loadable at runtime) would only make **Windows lie to itself** — wrong
battery icon, wrong power-plan behavior — while the EC keeps charging the
battery exactly as before, because nothing at the ACPI-table layer
reaches back down to the EC's real charge-current logic. This makes the
whole approach pointless independent of its real DSDT-patching risk
(malformed AML can produce a system that won't boot until the override is
cleared from recovery).

**Also rejected: kernel-mode I/O drivers** (RWEverything's `RwDrv.sys`,
WinRing0, WinIo/PortTalk) to read/patch EC RAM or trap I/O ports 0x62/0x66
directly. These grant arbitrary ring-0 memory/port access to any calling
process, which is exactly why Microsoft puts them on its vulnerable-driver
blocklist — loading one on a machine that also runs rohomieo (a service
explicitly hardened for internet-facing remote access) hands anyone who
compromises the host a ring-0 privilege-escalation vector. That tradeoff
is categorically worse than the problem it would solve.

**The path that would actually work, if wanted:** a smart plug or
networked UPS outlet under `battery-guard`'s control. Poll `--status`,
cut power at the wall when the limit is reached, restore it once the
charge drops to a lower threshold. This produces the literal "AC absent,
EC naturally fails over to battery" behavior with zero risk to this
machine's hardware or security posture, because it removes AC at the
actual electrical source instead of lying to software about it. Not
implemented in this crate as of this writing — would be a new sibling
module (e.g. `rohomieo-power-cycle`) that calls a plug's local/cloud API
on the same threshold logic `battery-guard --status` already exposes.

**Hardware picks, if pursuing this:** favor a plug with a *documented
local-network API* — no cloud dependency, no external outage taking your
automation down with it.

- TP-Link Kasa KP125M or EP25 — local TCP API (port 9999), well
  documented by the `python-kasa` community project; KP125M adds energy
  monitoring.
- TP-Link Tapo P110 — same family, newer KLAP protocol, also supported by
  `python-kasa`, energy monitoring built in.
- Shelly Plug S — genuinely open local HTTP/MQTT API from the factory
  (not reverse-engineered), higher build quality, best pick if you want
  Home Assistant integration beyond just this one automation.

Avoid Wyze and the stock Amazon Smart Plug for this use case — both are
effectively cloud-only, which would make the automation depend on a
third-party service staying up.
