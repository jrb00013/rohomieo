use crate::transport::WmiTransport;
use crate::vendor::{ChargeLimiter, ChargeStatus};
use anyhow::{Context, Result};

// ASUS's raw ATK WMI interface (class AsusAtkWmi_WMNB, methods DEVS/DSTS,
// device ID 0x00120057 — the same interface and DevID Linux's asus-wmi
// kernel driver uses) exists and is callable, but its ACPI-WMI security
// descriptor rejects every caller that isn't Armoury Crate's own SYSTEM
// service — confirmed by identical WBEM_E_INVALID_PARAMETER failures
// across three independent, fully-elevated invocation stacks (raw COM,
// legacy .NET WMI, and CIM cmdlets) on the ROG Strix G18, even for the
// simplest possible call. Rather than pursue raw EC port I/O to route
// around that (a real risk of EC desync/hardware damage — see this
// crate's README), this drives the exact mechanism Armoury Crate's own
// "ASUSOptimization" service already uses: a plain INI file it polls,
// applied by restarting that service.
const ASUS_INI_PATH: &str =
    r"C:\ProgramData\ASUS\ASUS System Control Interface\AsusOptimization\Customization.ini";
const ASUS_SERVICE_NAME: &str = "ASUSOptimization";
const ASUS_INI_SECTION: &str = "[BatteryHealthCharging]";

pub struct AsusLimiter;

/// Overridable via `ROHOMIEO_BATTERY_GUARD_ASUS_INI` so tests can point at
/// a temp file instead of the real system path.
fn ini_path() -> String {
    std::env::var("ROHOMIEO_BATTERY_GUARD_ASUS_INI").unwrap_or_else(|_| ASUS_INI_PATH.to_string())
}

fn read_ini(path: &str) -> Result<String> {
    std::fs::read_to_string(path).with_context(|| format!("reading {path}"))
}

/// Rewrites the `value=` line under `[BatteryHealthCharging]` to `pct`,
/// leaving every other line untouched.
fn set_ini_value(content: &str, pct: u8) -> String {
    let mut out = Vec::with_capacity(content.lines().count());
    let mut in_section = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            in_section = trimmed.eq_ignore_ascii_case(ASUS_INI_SECTION);
            out.push(line.to_string());
        } else if in_section && trimmed.starts_with("value=") {
            out.push(format!("value={pct}"));
        } else {
            out.push(line.to_string());
        }
    }
    out.join("\r\n")
}

fn get_ini_value(content: &str) -> Option<u8> {
    let mut in_section = false;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            in_section = trimmed.eq_ignore_ascii_case(ASUS_INI_SECTION);
        } else if in_section {
            if let Some(v) = trimmed.strip_prefix("value=") {
                return v.trim().parse().ok();
            }
        }
    }
    None
}

/// Skipped when `ROHOMIEO_BATTERY_GUARD_SKIP_SERVICE_RESTART` is set, so
/// tests exercise the INI-rewrite logic without touching a real service.
fn service_restart_skipped() -> bool {
    std::env::var("ROHOMIEO_BATTERY_GUARD_SKIP_SERVICE_RESTART").is_ok()
}

#[cfg(target_os = "windows")]
fn restart_asus_optimization_service() -> Result<()> {
    if service_restart_skipped() {
        tracing::debug!("skipping ASUSOptimization restart (test override)");
        return Ok(());
    }
    use std::process::Command;
    let stop = Command::new("sc.exe")
        .args(["stop", ASUS_SERVICE_NAME])
        .output()
        .context("running sc.exe stop")?;
    tracing::debug!(status = ?stop.status, "sc.exe stop ASUSOptimization");
    // Give the SCM a moment to actually stop it before restarting —
    // sc.exe's own stop command returns as soon as the stop is
    // requested, not once it completes.
    std::thread::sleep(std::time::Duration::from_secs(2));
    let start = Command::new("sc.exe")
        .args(["start", ASUS_SERVICE_NAME])
        .output()
        .context("running sc.exe start")?;
    tracing::debug!(status = ?start.status, "sc.exe start ASUSOptimization");
    if !start.status.success() {
        anyhow::bail!(
            "sc.exe start {ASUS_SERVICE_NAME} failed: {}",
            String::from_utf8_lossy(&start.stderr)
        );
    }
    Ok(())
}

#[cfg(not(target_os = "windows"))]
fn restart_asus_optimization_service() -> Result<()> {
    if service_restart_skipped() {
        tracing::debug!("skipping ASUSOptimization restart (test override)");
        return Ok(());
    }
    anyhow::bail!("battery-guard only supports Windows")
}

impl ChargeLimiter for AsusLimiter {
    fn set_limit(&self, _transport: &dyn WmiTransport, pct: u8) -> Result<()> {
        tracing::debug!(pct, "ASUS: applying charge limit via ASUSOptimization INI");
        let path = ini_path();
        let backup_path = format!("{path}.rohomieo-backup");
        if !std::path::Path::new(&backup_path).exists() {
            std::fs::copy(&path, &backup_path)
                .with_context(|| format!("backing up {path} to {backup_path}"))?;
        }
        let content = read_ini(&path)?;
        let updated = set_ini_value(&content, pct);
        std::fs::write(&path, updated).with_context(|| format!("writing {path}"))?;
        restart_asus_optimization_service()?;
        Ok(())
    }

    fn get_status(&self, _transport: &dyn WmiTransport) -> Result<ChargeStatus> {
        let content = read_ini(&ini_path())?;
        let limit_pct = get_ini_value(&content);
        Ok(ChargeStatus { current_pct: 0, limit_pct, is_charging: false })
    }

    fn planned_call(&self, pct: u8) -> String {
        format!(
            "write value={pct} under {ASUS_INI_SECTION} in {ASUS_INI_PATH}, then restart {ASUS_SERVICE_NAME}"
        )
    }

    fn auto_applies(&self) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_INI: &str = "[Main]\r\nlegal=1\r\n[BatteryHealthCharging]\r\nversion=3\r\nvalue=80\r\n[TaskFirst]\r\nvalue=0\r\n";

    #[test]
    fn set_ini_value_rewrites_only_target_section() {
        let updated = set_ini_value(SAMPLE_INI, 60);
        assert!(updated.contains("[BatteryHealthCharging]\r\nversion=3\r\nvalue=60"));
        assert!(updated.contains("[TaskFirst]\r\nvalue=0"));
    }

    #[test]
    fn get_ini_value_reads_target_section_only() {
        assert_eq!(get_ini_value(SAMPLE_INI), Some(80));
    }

    #[test]
    fn get_ini_value_none_when_section_missing() {
        assert_eq!(get_ini_value("[Main]\r\nlegal=1\r\n"), None);
    }

    #[test]
    fn planned_call_describes_mechanism_and_pct() {
        let desc = AsusLimiter.planned_call(60);
        assert!(desc.contains("60"));
        assert!(desc.contains("ASUSOptimization"));
    }

    #[test]
    fn asus_auto_applies() {
        assert!(AsusLimiter.auto_applies());
    }
}
