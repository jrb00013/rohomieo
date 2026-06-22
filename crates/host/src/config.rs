//! Optional TOML config for rohomieo-host.

use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::Path;

#[derive(Debug, Clone, Deserialize, Default)]
pub struct HostConfig {
    #[serde(default)]
    pub signaling: Option<String>,
    #[serde(default)]
    pub session: Option<String>,
    #[serde(default)]
    pub pin: Option<String>,
    #[serde(default)]
    pub device_name: Option<String>,
    #[serde(default)]
    pub fps: Option<u32>,
    #[serde(default)]
    pub idle_fps: Option<u32>,
}

impl HostConfig {
    pub fn load(path: &Path) -> Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("read config {}", path.display()))?;
        toml::from_str(&text).context("parse host config TOML")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_minimal() {
        let cfg: HostConfig = toml::from_str(
            r#"
signaling = "wss://10.0.0.1:8443/ws"
fps = 24
"#,
        )
        .unwrap();
        assert_eq!(cfg.signaling.as_deref(), Some("wss://10.0.0.1:8443/ws"));
        assert_eq!(cfg.fps, Some(24));
    }
}
