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

#[cfg(target_os = "windows")]
pub struct RealWmiTransport {
    conn: wmi::WMIConnection,
}

#[cfg(target_os = "windows")]
impl RealWmiTransport {
    pub fn connect(namespace: &str) -> anyhow::Result<Self> {
        let com_con = wmi::COMLibrary::new()?;
        let conn = wmi::WMIConnection::with_namespace_path(namespace, com_con.into())?;
        Ok(Self { conn })
    }
}

#[cfg(target_os = "windows")]
impl WmiTransport for RealWmiTransport {
    fn call_method(
        &self,
        _namespace: &str,
        class: &str,
        method: &str,
        args: &[(&str, WmiArg)],
    ) -> anyhow::Result<WmiValue> {
        tracing::debug!(class, method, ?args, "calling WMI method");
        // Vendor modules build the exact IWbemClassObject method call;
        // this transport just logs + delegates. Real invocation detail
        // lives in wmi-crate calls made per vendor in Task 3+, since the
        // `wmi` crate's ergonomic API is query-oriented — method calls
        // route through `wmi::WMIConnection::exec_method` when available,
        // else raw COM via `windows` crate. Documented further in each
        // vendor module.
        anyhow::bail!("call_method not yet wired for class={class} method={method}")
    }

    fn query_manufacturer_model(&self) -> anyhow::Result<(String, String)> {
        #[derive(serde::Deserialize)]
        struct ComputerSystem {
            #[serde(rename = "Manufacturer")]
            manufacturer: String,
            #[serde(rename = "Model")]
            model: String,
        }
        let results: Vec<ComputerSystem> =
            self.conn.raw_query("SELECT Manufacturer, Model FROM Win32_ComputerSystem")?;
        let cs = results
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("Win32_ComputerSystem returned no rows"))?;
        Ok((cs.manufacturer, cs.model))
    }
}

#[allow(dead_code)]
#[cfg(not(target_os = "windows"))]
pub struct RealWmiTransport;

#[cfg(not(target_os = "windows"))]
impl WmiTransport for RealWmiTransport {
    fn call_method(
        &self,
        _n: &str,
        _c: &str,
        _m: &str,
        _a: &[(&str, WmiArg)],
    ) -> anyhow::Result<WmiValue> {
        anyhow::bail!("battery-guard only supports Windows")
    }
    fn query_manufacturer_model(&self) -> anyhow::Result<(String, String)> {
        anyhow::bail!("battery-guard only supports Windows")
    }
}

#[cfg(test)]
use std::cell::RefCell;

#[cfg(test)]
pub struct MockWmiTransport {
    pub manufacturer: String,
    pub model: String,
    pub calls: RefCell<Vec<(String, String, String)>>, // (namespace, class, method)
    pub call_result: Option<WmiValue>,
}

#[cfg(test)]
impl Default for MockWmiTransport {
    fn default() -> Self {
        Self {
            manufacturer: String::new(),
            model: String::new(),
            calls: RefCell::new(vec![]),
            call_result: None,
        }
    }
}

#[cfg(test)]
impl WmiTransport for MockWmiTransport {
    fn call_method(
        &self,
        namespace: &str,
        class: &str,
        method: &str,
        _args: &[(&str, WmiArg)],
    ) -> Result<WmiValue> {
        self.calls.borrow_mut().push((namespace.to_string(), class.to_string(), method.to_string()));
        Ok(self.call_result.clone().unwrap_or(WmiValue::Unit))
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
            ..Default::default()
        };
        let (m, _) = t.query_manufacturer_model().unwrap();
        assert_eq!(m, "ASUSTeK COMPUTER INC.");
    }
}
