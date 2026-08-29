use crate::detect::Vendor;
use crate::transport::WmiTransport;
use anyhow::Result;

mod asus;

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
pub fn limiter_for(vendor: &Vendor) -> Option<Box<dyn ChargeLimiter>> {
    match vendor {
        Vendor::Asus => Some(Box::new(asus::AsusLimiter)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_vendor_has_no_limiter() {
        assert!(limiter_for(&Vendor::Unknown("x".into())).is_none());
    }
}
