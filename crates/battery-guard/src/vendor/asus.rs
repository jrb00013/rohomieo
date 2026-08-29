use crate::transport::{WmiArg, WmiTransport, WmiValue};
use crate::vendor::{ChargeLimiter, ChargeStatus};
use anyhow::Result;

const ASUS_WMI_NAMESPACE: &str = r"root\wmi";
const ASUS_WMI_CLASS: &str = "AsusAtkWmiApi";
const ASUS_SET_METHOD: &str = "SetBatteryLimit";
const ASUS_GET_METHOD: &str = "GetBatteryLimit";

pub struct AsusLimiter;

impl ChargeLimiter for AsusLimiter {
    fn set_limit(&self, transport: &dyn WmiTransport, pct: u8) -> Result<()> {
        tracing::debug!(pct, "ASUS: applying charge limit");
        transport.call_method(
            ASUS_WMI_NAMESPACE,
            ASUS_WMI_CLASS,
            ASUS_SET_METHOD,
            &[("Limit", WmiArg::U8(pct))],
        )?;
        Ok(())
    }

    fn get_status(&self, transport: &dyn WmiTransport) -> Result<ChargeStatus> {
        let result = transport.call_method(ASUS_WMI_NAMESPACE, ASUS_WMI_CLASS, ASUS_GET_METHOD, &[])?;
        let limit_pct = match result {
            WmiValue::U32(v) => Some(v as u8),
            _ => None,
        };
        Ok(ChargeStatus { current_pct: 0, limit_pct, is_charging: false })
    }

    fn planned_call(&self, pct: u8) -> String {
        format!("{ASUS_WMI_NAMESPACE}\\{ASUS_WMI_CLASS}::{ASUS_SET_METHOD}(Limit={pct})")
    }

    fn auto_applies(&self) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::MockWmiTransport;

    #[test]
    fn set_limit_calls_expected_wmi_method() {
        let t = MockWmiTransport::default();
        let limiter = AsusLimiter;
        limiter.set_limit(&t, 80).unwrap();
        let calls = t.calls.borrow();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0], (ASUS_WMI_NAMESPACE.to_string(), ASUS_WMI_CLASS.to_string(), ASUS_SET_METHOD.to_string()));
    }

    #[test]
    fn planned_call_describes_method_and_pct() {
        let limiter = AsusLimiter;
        let desc = limiter.planned_call(60);
        assert!(desc.contains("SetBatteryLimit"));
        assert!(desc.contains("60"));
    }

    #[test]
    fn asus_auto_applies() {
        assert!(AsusLimiter.auto_applies());
    }
}
