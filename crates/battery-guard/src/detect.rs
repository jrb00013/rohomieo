use crate::transport::WmiTransport;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Vendor {
    Asus,
    Lenovo,
    Dell,
    Hp,
    Unknown(String),
}

#[allow(dead_code)]
pub fn detect_vendor(transport: &dyn WmiTransport) -> Vendor {
    let (manufacturer, _model) = match transport.query_manufacturer_model() {
        Ok(v) => v,
        Err(_) => return Vendor::Unknown("<wmi query failed>".to_string()),
    };
    let m = manufacturer.to_uppercase();
    if m.contains("ASUS") {
        Vendor::Asus
    } else if m.contains("LENOVO") {
        Vendor::Lenovo
    } else if m.contains("DELL") {
        Vendor::Dell
    } else if m.contains("HP") || m.contains("HEWLETT-PACKARD") {
        Vendor::Hp
    } else {
        Vendor::Unknown(manufacturer)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::MockWmiTransport;

    #[test]
    fn detects_asus() {
        let t = MockWmiTransport {
            manufacturer: "ASUSTeK COMPUTER INC.".into(),
            model: "ROG Strix G18".into(),
        };
        assert_eq!(detect_vendor(&t), Vendor::Asus);
    }

    #[test]
    fn detects_lenovo() {
        let t = MockWmiTransport { manufacturer: "LENOVO".into(), model: "ThinkPad X1".into() };
        assert_eq!(detect_vendor(&t), Vendor::Lenovo);
    }

    #[test]
    fn detects_dell() {
        let t = MockWmiTransport { manufacturer: "Dell Inc.".into(), model: "XPS 15".into() };
        assert_eq!(detect_vendor(&t), Vendor::Dell);
    }

    #[test]
    fn detects_hp() {
        let t = MockWmiTransport { manufacturer: "HP".into(), model: "EliteBook".into() };
        assert_eq!(detect_vendor(&t), Vendor::Hp);
    }

    #[test]
    fn unknown_vendor_falls_through() {
        let t = MockWmiTransport { manufacturer: "Framework".into(), model: "Laptop 13".into() };
        assert_eq!(detect_vendor(&t), Vendor::Unknown("Framework".into()));
    }
}
