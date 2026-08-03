//! Phone invite: HTTPS join URL + terminal QR (scan opens browser + auto-connects).

use qrcode::render::unicode::Dense1x2;
use qrcode::QrCode;
use std::net::{IpAddr, Ipv4Addr, UdpSocket};
use url::Url;

pub struct TurnInfo<'a> {
    pub url: &'a str,
    pub user: &'a str,
    pub pass: &'a str,
}

/// Build `https://<lan-or-host>:8443/?s=...&p=...&auto=1` for the PWA.
/// When TURN is set (global mode), also embeds `ws`, `turn`, `turnu`, `turnp`.
pub fn join_url(
    signaling_ws: &str,
    session_id: &str,
    pin: &str,
    public_base: Option<&str>,
    turn: Option<TurnInfo<'_>>,
) -> String {
    let base = public_base
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.trim_end_matches('/').to_string())
        .unwrap_or_else(|| https_base_from_signaling(signaling_ws));

    // Use ?query (not #hash). Phone camera / QR apps often drop the fragment,
    // which left the PWA with an empty session and looked "broken" after scan.
    let mut u = Url::parse(&format!("{base}/")).unwrap_or_else(|_| {
        Url::parse("https://127.0.0.1:8443/").expect("fallback")
    });
    {
        let mut q = u.query_pairs_mut();
        q.append_pair("s", session_id)
            .append_pair("p", pin)
            .append_pair("auto", "1");
        if let Some(t) = turn {
            // Public invite: phone must dial the WAN signaling host, not 127.0.0.1.
            let invite_ws = invite_signaling_ws(signaling_ws, &base);
            q.append_pair("ws", &invite_ws)
                .append_pair("turn", t.url)
                .append_pair("turnu", t.user)
                .append_pair("turnp", t.pass);
        }
    }
    u.to_string()
}

fn invite_signaling_ws(host_signaling: &str, public_https_base: &str) -> String {
    if let Ok(pub_u) = Url::parse(public_https_base) {
        let ws_scheme = if pub_u.scheme() == "http" { "ws" } else { "wss" };
        let host = pub_u.host_str().unwrap_or("127.0.0.1");
        let port = pub_u.port_or_known_default().unwrap_or(8443);
        return format!("{ws_scheme}://{host}:{port}/ws");
    }
    host_signaling.to_string()
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
            None,
        );
        assert_eq!(
            u,
            "https://192.168.1.10:8443/?s=abc-def&p=123456&auto=1"
        );
    }

    #[test]
    fn join_url_embeds_turn_and_public_ws() {
        let u = join_url(
            "wss://127.0.0.1:8443/ws",
            "abc-def",
            "123456",
            Some("https://203.0.113.9:8443"),
            Some(TurnInfo {
                url: "turn:203.0.113.9:3478",
                user: "rhuser",
                pass: "rhpass",
            }),
        );
        let parsed = Url::parse(&u).unwrap();
        let q: std::collections::HashMap<_, _> = parsed.query_pairs().into_owned().collect();
        assert_eq!(q.get("s").map(String::as_str), Some("abc-def"));
        assert_eq!(q.get("ws").map(String::as_str), Some("wss://203.0.113.9:8443/ws"));
        assert_eq!(q.get("turn").map(String::as_str), Some("turn:203.0.113.9:3478"));
        assert_eq!(q.get("turnu").map(String::as_str), Some("rhuser"));
        assert_eq!(q.get("turnp").map(String::as_str), Some("rhpass"));
    }
}
