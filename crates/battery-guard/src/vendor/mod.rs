use crate::detect::Vendor;
use crate::transport::WmiTransport;
use anyhow::Result;

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq)]
pub struct ChargeStatus {
    pub current_pct: u8,
    pub limit_pct: Option<u8>,
    pub is_charging: bool,
}

#[allow(dead_code)]
pub trait ChargeLimiter {
    fn set_limit(&self, transport: &dyn WmiTransport, pct: u8) -> Result<()>;
    fn get_status(&self, transport: &dyn WmiTransport) -> Result<ChargeStatus>;
    fn planned_call(&self, pct: u8) -> String;
    fn auto_applies(&self) -> bool;
}

#[allow(dead_code)]
pub fn limiter_for(_vendor: &Vendor) -> Option<Box<dyn ChargeLimiter>> {
    None
}

#[cfg(test)]
struct StubLimiter;

#[cfg(test)]
impl ChargeLimiter for StubLimiter {
    fn set_limit(&self, _t: &dyn WmiTransport, _pct: u8) -> Result<()> {
        Ok(())
    }
    fn get_status(&self, _t: &dyn WmiTransport) -> Result<ChargeStatus> {
        Ok(ChargeStatus { current_pct: 0, limit_pct: None, is_charging: false })
    }
    fn planned_call(&self, _pct: u8) -> String {
        "stub".into()
    }
    fn auto_applies(&self) -> bool {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_vendor_has_no_limiter() {
        assert!(limiter_for(&Vendor::Unknown("x".into())).is_none());
    }

    #[test]
    fn stub_limiter_satisfies_trait() {
        let limiter: Box<dyn ChargeLimiter> = Box::new(StubLimiter);
        assert!(!limiter.auto_applies());
        assert_eq!(limiter.planned_call(80), "stub");
    }
}
