# battery-guard: adaptive charge-limit CLI

Date: 2026-08-28
Status: approved

## Purpose

rohomieo hosts often run 24/7 on a laptop kept permanently on AC power.
Leaving the battery charged at 100% continuously accelerates chemical wear.
`rohomieo-battery-guard` is a native Rust CLI, built as a new crate in the
rohomieo workspace, that caps battery charge at a configurable percentage by
calling each laptop vendor's ACPI/WMI charge-threshold method directly — the
same EC-backed mechanism the vendor's own GUI app (Armoury Crate, Lenovo
Vantage, Dell Power Manager, HP Command Center) uses internally. No vendor
GUI app needs to run in the background, and the setting persists at the EC
level once applied.

## Scope

In scope:
- Vendor detection via `Win32_ComputerSystem.Manufacturer`/`Model`.
- WMI-based charge-limit implementations for ASUS, Lenovo, Dell, HP.
- A `ChargeLimiter` trait abstraction so vendors are independent, swappable
  implementations behind one interface.
- CLI: `--limit <1-100>` (default 80), `--status`, `--detect`.
- Debug logging via `tracing` (`RUST_LOG=rohomieo_battery_guard=debug`).
- Unit tests per vendor against a mocked WMI transport (no real hardware
  needed for Lenovo/Dell/HP to be exercised in CI).
- `scripts/windows/battery-guard.ps1` wrapper, mirroring the existing
  `enable-upnp.ps1` pattern, and an optional invocation from
  `scripts/run.sh --global` on Windows hosts.

Out of scope (documented only, not built):
- Raw EC port I/O (0x62/0x66) via a custom kernel driver. This is the
  fallback path if a vendor's WMI method turns out not to exist or not to
  work as documented. It requires a signed kernel driver, is
  vendor-undocumented/reverse-engineered, and carries real risk of
  desyncing the EC or damaging charge circuitry. A markdown note under
  `crates/battery-guard/README.md` records this as the escalation path,
  with no code.

## Vendor support matrix

| Vendor | WMI method (as documented) | Verified on real hardware |
|--------|------------------------------|----------------------------|
| ASUS   | `ROOT\WMI` ATK WMI interface (`AsusAtkWmiApi`, ACPI `ALIB` method, battery limit sub-function) | Yes — ROG Strix G18 |
| Lenovo | `ROOT\WMI` `Lenovo_BatteryInformation` / `BatteryChargeThreshold` set method | No |
| Dell   | Dell Client Command CAPI `PowerManagement` charge-threshold method | No |
| HP     | `root\hp\InstrumentedBIOS` `HP_BIOSSettingInterface` battery charge control setting | No |

## Architecture

```
crates/battery-guard/
  Cargo.toml
  README.md              # includes the EC/kernel-driver fallback note
  src/
    main.rs               # CLI entry (clap): --limit, --status, --detect
    detect.rs             # WMI query of Win32_ComputerSystem -> Vendor enum
    transport.rs           # WmiTransport trait + real + mock impls
    vendor/
      mod.rs               # ChargeLimiter trait, Vendor enum, dispatch
      asus.rs
      lenovo.rs
      dell.rs
      hp.rs

scripts/windows/
  battery-guard.ps1        # thin wrapper: builds/locates the exe, invokes it
```

### `ChargeLimiter` trait

```rust
trait ChargeLimiter {
    fn set_limit(&self, transport: &dyn WmiTransport, pct: u8) -> Result<()>;
    fn get_status(&self, transport: &dyn WmiTransport) -> Result<ChargeStatus>;
}
```

Each vendor module implements this trait against the `WmiTransport` trait
(rather than calling the `wmi` crate directly), so unit tests can supply a
`MockWmiTransport` that records/replays expected WMI calls without touching
real hardware.

### Auto-apply behavior

`detect::vendor()` always runs and reports what it found. What happens next
depends on the vendor:

- **ASUS**: `set_limit` is invoked automatically (hardware-verified path).
- **Lenovo / Dell / HP**: the tool detects the vendor, resolves and prints
  the WMI method/args it *would* call and the resolved limit, and exits
  without invoking it. This is not a CLI flag — it's simply how "auto"
  behaves until that vendor's path has been confirmed working on real
  hardware. Flipping a vendor from "print only" to "apply" is a one-line
  change in `vendor/mod.rs::dispatch` once verified.
- **Unknown vendor**: prints guidance (link to OEM tool, note about the
  EC/kernel fallback doc) and exits non-zero.

### CLI

```
rohomieo-battery-guard [--limit <1-100>] [--status] [--detect]
```

- No args: detect vendor, apply default limit (80) if ASUS, else print
  planned action.
- `--limit N`: override the target percentage (1-100, validated).
- `--status`: query and print current charge/threshold state, no mutation.
- `--detect`: print detected vendor/model and exit, no WMI mutation calls
  at all.

### Logging

Uses the workspace's `tracing` + `tracing-subscriber` (env-filter) already
present in `Cargo.toml`. `RUST_LOG=rohomieo_battery_guard=debug` (or
`=trace`) prints: detected vendor/model, chosen WMI namespace/class/method,
raw method arguments, raw WMI return codes, and the decision of whether to
apply or print-only. `battery-guard.ps1` forwards `$env:RUST_LOG` through
unchanged so the wrapper doesn't need its own verbosity flag.

### Testing

- `cargo clippy --workspace -D warnings` covers the new crate.
- Unit tests per vendor module using `MockWmiTransport`: verify correct
  namespace/class/method/argument construction for a range of `--limit`
  values (including boundary 1/100 and invalid >100 rejected before any
  WMI call), and correct parsing of `--status` mock responses.
- No hardware-in-the-loop tests for Lenovo/Dell/HP; ASUS gets an
  integration test gated behind a `--ignored`-by-default `cfg` so it only
  runs when explicitly requested on real ASUS hardware.

### Integration with existing scripts

- `scripts/windows/battery-guard.ps1` follows the same shape as
  `scripts/windows/enable-upnp.ps1`: locates or builds the release binary,
  invokes it, surfaces its exit code.
- `scripts/run.sh --global` gains an optional step (Windows-only, same
  spot as the existing UPnP prep automation) that shells out to
  `battery-guard.ps1` with default args, non-fatal if it fails (never
  blocks the actual rohomieo tunnel/host startup).

## Error handling

- WMI connection failure (no `ROOT\WMI` namespace, service not running):
  reported as a clear error, non-fatal to the calling script.
- Vendor detected but method call fails (e.g. wrong sub-function on
  firmware version mismatch): the raw WMI error code is logged at `error`
  level with the attempted method/args, and the tool exits non-zero rather
  than retrying blindly.
- `--limit` outside 1-100 is rejected by `clap` value parsing before any
  vendor code runs.
