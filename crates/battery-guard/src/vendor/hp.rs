use crate::transport::{WmiArg, WmiTransport, WmiValue};
use crate::vendor::{ChargeLimiter, ChargeStatus};
use anyhow::Result;

const HP_WMI_NAMESPACE: &str = r"root\hp\instrumentedbios";
const HP_WMI_CLASS: &str = "HP_BIOSSettingInterface";
const HP_SET_METHOD: &str = "SetBIOSSetting";
const HP_GET_METHOD: &str = "GetBIOSSetting";

pub struct HpLimiter;

impl ChargeLimiter for HpLimiter {
    fn set_limit(&self, transport: &dyn WmiTransport, pct: u8) -> Result<()> {
        tracing::debug!(pct, "HP: applying charge limit (untested on hardware)");
        transport.call_method(
            HP_WMI_NAMESPACE,
            HP_WMI_CLASS,
            HP_SET_METHOD,
            &[("Name", WmiArg::Str("Battery Charge Threshold".into())), ("Value", WmiArg::U8(pct))],
        )?;
        Ok(())
    }

    fn get_status(&self, transport: &dyn WmiTransport) -> Result<ChargeStatus> {
        let result = transport.call_method(HP_WMI_NAMESPACE, HP_WMI_CLASS, HP_GET_METHOD, &[])?;
        let limit_pct = match result {
            WmiValue::U32(v) => Some(v as u8),
            _ => None,
        };
        Ok(ChargeStatus { current_pct: 0, limit_pct, is_charging: false })
    }

    fn planned_call(&self, pct: u8) -> String {
        format!("{HP_WMI_NAMESPACE}\\{HP_WMI_CLASS}::{HP_SET_METHOD}(Name='Battery Charge Threshold', Value={pct})")
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
        HpLimiter.set_limit(&t, 75).unwrap();
        let calls = t.calls.borrow();
        assert_eq!(calls[0].2, HP_SET_METHOD);
    }

    #[test]
    fn hp_does_not_auto_apply() {
        assert!(!HpLimiter.auto_applies());
    }
}
