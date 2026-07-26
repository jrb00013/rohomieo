//! Phone invite: HTTPS join URL + terminal QR (scan opens browser + auto-connects).

use qrcode::render::unicode::Dense1x2;
use qrcode::QrCode;
use std::net::{IpAddr, Ipv4Addr, UdpSocket};
use url::Url;

/// Build `https://<lan-or-host>:8443/?s=...&p=...&auto=1` for the PWA.
pub fn join_url(signaling_ws: &str, session_id: &str, pin: &str, public_base: Option<&str>) -> String {
    let base = public_base
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.trim_end_matches('/').to_string())
        .unwrap_or_else(|| https_base_from_signaling(signaling_ws));

    format!(
        "{base}/#s={}&p={}&auto=1",
        urlencoding_lite(session_id),
        urlencoding_lite(pin)
    )
}

fn urlencoding_lite(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn https_base_from_signaling(signaling_ws: &str) -> String {
    let Ok(u) = Url::parse(signaling_ws) else {
        return format!("https://{}/", guess_lan_ip().unwrap_or(Ipv4Addr::LOCALHOST));
    };
    let port = u.port_or_known_default().unwrap_or(8443);
    let host = u.host_str().unwrap_or("127.0.0.1");
    let host = if is_loopback_host(host) {
        guess_lan_ip()
            .map(|ip| ip.to_string())
            .unwrap_or_else(|| host.to_string())
    } else {
        host.to_string()
    };
    let scheme = if u.scheme() == "ws" { "http" } else { "https" };
    format!("{scheme}://{host}:{port}")
}

fn is_loopback_host(host: &str) -> bool {
    matches!(host, "127.0.0.1" | "localhost" | "::1")
        || host.parse::<IpAddr>().ok().is_some_and(|ip| ip.is_loopback())
}

/// Best-effort LAN IPv4 (UDP connect trick — no packets need to succeed).
pub fn guess_lan_ip() -> Option<Ipv4Addr> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    match socket.local_addr().ok()?.ip() {
        IpAddr::V4(ip) if !ip.is_loopback() && !ip.is_unspecified() && !ip.is_link_local() => {
            Some(ip)
        }
        _ => None,
    }
}

/// Print a scannable QR + plain URL to the host console.
pub fn print_invite_qr(join: &str) {
    eprintln!();
    eprintln!("══════════════════════════════════════════════════");
    eprintln!("  Scan with phone camera / QR app");
    eprintln!("  Opens Rohomieo in the browser and connects");
    eprintln!("══════════════════════════════════════════════════");
    match QrCode::new(join.as_bytes()) {
        Ok(code) => {
            let art = code
                .render::<Dense1x2>()
                .dark_color(Dense1x2::Dark)
                .light_color(Dense1x2::Light)
                .quiet_zone(true)
                .build();
            eprintln!("{art}");
        }
        Err(e) => eprintln!("  (QR render failed: {e})"),
    }
    eprintln!("  URL: {join}");
    eprintln!("══════════════════════════════════════════════════");
    eprintln!();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn join_url_uses_lan_when_signaling_is_loopback() {
        let u = join_url(
            "wss://127.0.0.1:8443/ws",
            "abc-def",
            "123456",
            Some("https://192.168.1.10:8443"),
        );
        assert_eq!(
            u,
            "https://192.168.1.10:8443/#s=abc-def&p=123456&auto=1"
        );
    }
}
