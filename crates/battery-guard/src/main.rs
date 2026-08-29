mod detect;
mod transport;
mod vendor;

use clap::Parser;
use detect::detect_vendor;
use transport::{RealWmiTransport, WmiTransport};

#[derive(Parser, Debug)]
#[command(name = "rohomieo-battery-guard", about = "Cap laptop battery charge for always-on rohomieo hosts")]
pub struct Args {
    /// Target charge limit percentage (1-100)
    #[arg(long, value_parser = clap::value_parser!(u8).range(1..=100), default_value_t = 80)]
    pub limit: u8,

    /// Only print current charge status, don't change anything
    #[arg(long)]
    pub status: bool,

    /// Only detect and print vendor/model, don't call any WMI method
    #[arg(long)]
    pub detect: bool,
}

pub fn run(args: Args, transport: &dyn WmiTransport) -> anyhow::Result<()> {
    let vendor = detect_vendor(transport);
    tracing::debug!(?vendor, "detected vendor");

    if args.detect {
        println!("Detected vendor: {vendor:?}");
        return Ok(());
    }

    let limiter = match vendor::limiter_for(&vendor) {
        Some(l) => l,
        None => {
            println!("Unknown vendor ({vendor:?}) — no charge-limiter available.");
            println!("See crates/battery-guard/README.md for the documented EC/kernel-driver fallback path.");
            anyhow::bail!("unsupported vendor");
        }
    };

    if args.status {
        let status = limiter.get_status(transport)?;
        println!("{status:?}");
        return Ok(());
    }

    if limiter.auto_applies() {
        limiter.set_limit(transport, args.limit)?;
        println!("Applied charge limit: {}%", args.limit);
    } else {
        println!("Vendor detected but not hardware-verified — not applying automatically.");
        println!("Would call: {}", limiter.planned_call(args.limit));
    }

    Ok(())
}

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    let args = Args::parse();
    let transport = RealWmiTransport::connect(r"root\wmi")?;
    run(args, &transport)
}

#[cfg(test)]
mod tests {
    use super::*;
    use transport::MockWmiTransport;

    #[test]
    fn detect_only_does_not_call_set_limit() {
        let t = MockWmiTransport { manufacturer: "ASUSTeK COMPUTER INC.".into(), ..Default::default() };
        let args = Args { limit: 80, status: false, detect: true };
        run(args, &t).unwrap();
        assert_eq!(t.calls.borrow().len(), 0);
    }

    #[test]
    fn asus_auto_applies_on_default_run() {
        // ASUS's real path is file I/O + a service restart, not WMI (see
        // vendor::asus for why) — point it at a temp file and skip the
        // service restart so this stays a hermetic unit test.
        let tmp = std::env::temp_dir().join("rohomieo-battery-guard-test.ini");
        std::fs::write(&tmp, "[BatteryHealthCharging]\r\nversion=3\r\nvalue=80\r\n").unwrap();
        std::env::set_var("ROHOMIEO_BATTERY_GUARD_ASUS_INI", &tmp);
        std::env::set_var("ROHOMIEO_BATTERY_GUARD_SKIP_SERVICE_RESTART", "1");

        let t = MockWmiTransport { manufacturer: "ASUSTeK COMPUTER INC.".into(), ..Default::default() };
        let args = Args { limit: 60, status: false, detect: false };
        run(args, &t).unwrap();
        let updated = std::fs::read_to_string(&tmp).unwrap();
        assert!(updated.contains("value=60"));

        std::env::remove_var("ROHOMIEO_BATTERY_GUARD_ASUS_INI");
        std::env::remove_var("ROHOMIEO_BATTERY_GUARD_SKIP_SERVICE_RESTART");
        let _ = std::fs::remove_file(&tmp);
        let _ = std::fs::remove_file(format!("{}.rohomieo-backup", tmp.display()));
    }

    #[test]
    fn lenovo_does_not_call_set_limit_without_confirmation() {
        let t = MockWmiTransport { manufacturer: "LENOVO".into(), ..Default::default() };
        let args = Args { limit: 60, status: false, detect: false };
        run(args, &t).unwrap();
        assert_eq!(t.calls.borrow().len(), 0);
    }

    #[test]
    fn unknown_vendor_errors() {
        let t = MockWmiTransport { manufacturer: "Framework".into(), ..Default::default() };
        let args = Args { limit: 60, status: false, detect: false };
        assert!(run(args, &t).is_err());
    }
}
