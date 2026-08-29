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
