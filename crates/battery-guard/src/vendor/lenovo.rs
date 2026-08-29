use crate::transport::{WmiArg, WmiTransport, WmiValue};
use crate::vendor::{ChargeLimiter, ChargeStatus};
use anyhow::Result;

const LENOVO_WMI_NAMESPACE: &str = r"root\wmi";
const LENOVO_WMI_CLASS: &str = "Lenovo_BatteryInformation";
const LENOVO_SET_METHOD: &str = "SetBatteryChargeThreshold";
const LENOVO_GET_METHOD: &str = "GetBatteryChargeThreshold";

pub struct LenovoLimiter;

impl ChargeLimiter for LenovoLimiter {
    fn set_limit(&self, transport: &dyn WmiTransport, pct: u8) -> Result<()> {
        tracing::debug!(pct, "Lenovo: applying charge limit (untested on hardware)");
        transport.call_method(
            LENOVO_WMI_NAMESPACE,
            LENOVO_WMI_CLASS,
            LENOVO_SET_METHOD,
            &[("Threshold", WmiArg::U8(pct))],
        )?;
        Ok(())
    }

    fn get_status(&self, transport: &dyn WmiTransport) -> Result<ChargeStatus> {
        let result = transport.call_method(LENOVO_WMI_NAMESPACE, LENOVO_WMI_CLASS, LENOVO_GET_METHOD, &[])?;
        let limit_pct = match result {
            WmiValue::U32(v) => Some(v as u8),
            _ => None,
        };
        Ok(ChargeStatus { current_pct: 0, limit_pct, is_charging: false })
    }

    fn planned_call(&self, pct: u8) -> String {
        format!("{LENOVO_WMI_NAMESPACE}\\{LENOVO_WMI_CLASS}::{LENOVO_SET_METHOD}(Threshold={pct})")
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
        LenovoLimiter.set_limit(&t, 70).unwrap();
        let calls = t.calls.borrow();
        assert_eq!(calls[0].2, LENOVO_SET_METHOD);
    }

    #[test]
    fn lenovo_does_not_auto_apply() {
        assert!(!LenovoLimiter.auto_applies());
    }
}
