use anyhow::Result;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub enum WmiArg {
    U8(u8),
    Str(String),
}

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WmiValue {
    U32(u32),
    Str(String),
    Unit,
}

#[allow(dead_code)]
pub trait WmiTransport {
    fn call_method(
        &self,
        namespace: &str,
        class: &str,
        method: &str,
        args: &[(&str, WmiArg)],
    ) -> Result<WmiValue>;

    fn query_manufacturer_model(&self) -> Result<(String, String)>;
}

#[cfg(test)]
pub struct MockWmiTransport {
    pub manufacturer: String,
    pub model: String,
}

#[cfg(test)]
impl WmiTransport for MockWmiTransport {
    fn call_method(
        &self,
        _namespace: &str,
        _class: &str,
        _method: &str,
        _args: &[(&str, WmiArg)],
    ) -> Result<WmiValue> {
        Ok(WmiValue::Unit)
    }

    fn query_manufacturer_model(&self) -> Result<(String, String)> {
        Ok((self.manufacturer.clone(), self.model.clone()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mock_transport_returns_configured_manufacturer() {
        let t = MockWmiTransport {
            manufacturer: "ASUSTeK COMPUTER INC.".into(),
            model: "ROG Strix G18".into(),
        };
        let (m, _) = t.query_manufacturer_model().unwrap();
        assert_eq!(m, "ASUSTeK COMPUTER INC.");
    }
}
