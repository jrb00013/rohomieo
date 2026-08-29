use crate::transport::{WmiArg, WmiTransport, WmiValue};
use crate::vendor::{ChargeLimiter, ChargeStatus};
use anyhow::Result;

const DELL_WMI_NAMESPACE: &str = r"root\dellclientwmi\pmwmi";
const DELL_WMI_CLASS: &str = "PowerManagement";
const DELL_SET_METHOD: &str = "SetPrimaryBatterySOCThreshold";
const DELL_GET_METHOD: &str = "GetPrimaryBatterySOCThreshold";

pub struct DellLimiter;

impl ChargeLimiter for DellLimiter {
    fn set_limit(&self, transport: &dyn WmiTransport, pct: u8) -> Result<()> {
        tracing::debug!(pct, "Dell: applying charge limit (untested on hardware)");
        transport.call_method(
            DELL_WMI_NAMESPACE,
            DELL_WMI_CLASS,
            DELL_SET_METHOD,
            &[("Threshold", WmiArg::U8(pct))],
        )?;
        Ok(())
    }

    fn get_status(&self, transport: &dyn WmiTransport) -> Result<ChargeStatus> {
        let result = transport.call_method(DELL_WMI_NAMESPACE, DELL_WMI_CLASS, DELL_GET_METHOD, &[])?;
        let limit_pct = match result {
            WmiValue::U32(v) => Some(v as u8),
            _ => None,
        };
        Ok(ChargeStatus { current_pct: 0, limit_pct, is_charging: false })
    }

    fn planned_call(&self, pct: u8) -> String {
        format!("{DELL_WMI_NAMESPACE}\\{DELL_WMI_CLASS}::{DELL_SET_METHOD}(Threshold={pct})")
    }

    fn auto_applies(&self) -> bool {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::MockWmiTransport;

    #[test]
    fn set_limit_calls_expected_wmi_method() {
        let t = MockWmiTransport::default();
        DellLimiter.set_limit(&t, 65).unwrap();
        let calls = t.calls.borrow();
        assert_eq!(calls[0].2, DELL_SET_METHOD);
    }

    #[test]
    fn dell_does_not_auto_apply() {
        assert!(!DellLimiter.auto_applies());
    }
}
