use anyhow::Result;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub enum WmiArg {
    U8(u8),
    U32(u32),
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
    cimv2_conn: wmi::WMIConnection,
}

#[cfg(target_os = "windows")]
impl RealWmiTransport {
    pub fn connect(namespace: &str) -> anyhow::Result<Self> {
        let com_con = wmi::COMLibrary::new()?;
        let conn = wmi::WMIConnection::with_namespace_path(namespace, com_con.into())?;
        // Win32_ComputerSystem (vendor/model detection) lives in root\cimv2,
        // not in the vendor-specific namespace (e.g. root\wmi) used for the
        // actual charge-limit method calls — keep a separate connection.
        let com_con2 = wmi::COMLibrary::new()?;
        let cimv2_conn = wmi::WMIConnection::with_namespace_path(r"root\cimv2", com_con2.into())?;
        Ok(Self { conn, cimv2_conn })
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
        use windows::core::{BSTR, HSTRING, VARIANT};
        use windows::Win32::System::Wmi::{
            IWbemClassObject, IWbemContext, WBEM_FLAG_RETURN_IMMEDIATELY, WBEM_FLAG_RETURN_WBEM_COMPLETE,
        };

        tracing::debug!(class, method, ?args, "calling WMI method");

        use anyhow::Context;

        let class_bstr = BSTR::from(class);
        let mut class_obj: Option<IWbemClassObject> = None;
        unsafe {
            self.conn
                .svc
                .GetObject(
                    &class_bstr,
                    WBEM_FLAG_RETURN_WBEM_COMPLETE,
                    None::<&IWbemContext>,
                    Some(&mut class_obj),
                    None,
                )
                .with_context(|| format!("GetObject({class}) failed"))?;
        }
        let class_obj = class_obj
            .ok_or_else(|| anyhow::anyhow!("GetObject returned no class object for {class}"))?;

        let method_hstr = HSTRING::from(method);
        let mut in_sig: Option<IWbemClassObject> = None;
        let mut out_sig: Option<IWbemClassObject> = None;
        unsafe {
            class_obj
                .GetMethod(&method_hstr, 0, &mut in_sig, &mut out_sig)
                .with_context(|| format!("GetMethod({class}::{method}) failed"))?;
        }

        let in_params: Option<IWbemClassObject> = match in_sig {
            Some(sig) => {
                let spawned = unsafe {
                    sig.SpawnInstance(0)
                        .with_context(|| format!("SpawnInstance for {class}::{method} in-params failed"))?
                };
                for (name, val) in args {
                    let name_hstr = HSTRING::from(*name);
                    // WMI marshals CIM uint8/uint32 properties as VT_I4
                    // (signed), not VT_UI4 — passing an unsigned VARIANT
                    // here trips WBEM_E_TYPE_MISMATCH on Put.
                    let variant: VARIANT = match val {
                        WmiArg::U8(v) => VARIANT::from(*v as i32),
                        WmiArg::U32(v) => VARIANT::from(*v as i32),
                        WmiArg::Str(s) => VARIANT::from(s.as_str()),
                    };
                    unsafe {
                        spawned
                            .Put(&name_hstr, 0, &variant, 0)
                            .with_context(|| format!("Put({name}) on {class}::{method} in-params failed"))?;
                    }
                }
                Some(spawned)
            }
            None => None,
        };

        let mut out_params: Option<IWbemClassObject> = None;
        unsafe {
            self.conn
                .svc
                .ExecMethod(
                    &class_bstr,
                    &BSTR::from(method),
                    // NOTE: WBEM_FLAG_RETURN_WBEM_COMPLETE (0) — the flag
                    // MSDN documents as correct for a synchronous call —
                    // makes this provider reject the call outright with
                    // WBEM_E_INVALID_PARAMETER on the ROG Strix G18.
                    // WBEM_FLAG_RETURN_IMMEDIATELY lets the call succeed,
                    // but out_params then comes back None rather than
                    // populated. Both symptoms point at this vendor's ATK
                    // WMI provider behaving non-standardly around method
                    // completion signaling; needs a live hardware session
                    // to iterate further (try WBEM_FLAG_DIRECT_READ, or a
                    // provider-specific IWbemContext value).
                    WBEM_FLAG_RETURN_IMMEDIATELY,
                    None::<&IWbemContext>,
                    in_params.as_ref(),
                    Some(&mut out_params),
                    None,
                )
                .with_context(|| format!("ExecMethod({class}::{method}) failed"))?;
        }

        if let Some(out) = out_params {
            // The out-parameter name is method-specific (DSTS names its
            // single [out] value "device_status", DEVS names it "result"),
            // not a generic COM "ReturnValue" — try the known names.
            for candidate in ["ReturnValue", "device_status", "result"] {
                let name_hstr = HSTRING::from(candidate);
                let mut variant = VARIANT::default();
                let got = unsafe { out.Get(&name_hstr, 0, &mut variant, None, None) };
                match got {
                    Ok(()) => match u32::try_from(&variant) {
                        Ok(v) => {
                            tracing::debug!(candidate, value = v, "out-param read");
                            return Ok(WmiValue::U32(v));
                        }
                        Err(e) => tracing::debug!(candidate, error = %e, "out-param Get ok but not u32"),
                    },
                    Err(e) => tracing::debug!(candidate, error = %e, "out-param Get failed"),
                }
            }
        }
        Ok(WmiValue::Unit)
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
            self.cimv2_conn.raw_query("SELECT Manufacturer, Model FROM Win32_ComputerSystem")?;
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
impl RealWmiTransport {
    pub fn connect(_namespace: &str) -> anyhow::Result<Self> {
        Ok(RealWmiTransport)
    }
}

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
