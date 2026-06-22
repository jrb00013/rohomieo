//! Prometheus-style metrics for signaling observability.

use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};

pub struct Metrics {
    pub ws_connections: AtomicUsize,
    pub sessions_active: AtomicUsize,
    pub hosts_registered: AtomicU64,
    pub viewers_registered: AtomicU64,
    pub pin_failures: AtomicU64,
    pub relay_messages: AtomicU64,
    pub sessions_expired: AtomicU64,
}

impl Metrics {
    pub fn new() -> Self {
        Self {
            ws_connections: AtomicUsize::new(0),
            sessions_active: AtomicUsize::new(0),
            hosts_registered: AtomicU64::new(0),
            viewers_registered: AtomicU64::new(0),
            pin_failures: AtomicU64::new(0),
            relay_messages: AtomicU64::new(0),
            sessions_expired: AtomicU64::new(0),
        }
    }

    pub fn render_prometheus(&self) -> String {
        let mut out = String::new();
        macro_rules! line {
            ($name:expr, $val:expr, $help:expr) => {
                out.push_str(&format!(
                    "# HELP {} {}\n# TYPE {} gauge\n{} {}\n",
                    $name, $help, $name, $name, $val
                ));
            };
            ($name:expr, $val:expr, $help:expr, counter) => {
                out.push_str(&format!(
                    "# HELP {} {}\n# TYPE {} counter\n{} {}\n",
                    $name, $help, $name, $name, $val
                ));
            };
        }
        line!(
            "rohomieo_ws_connections",
            self.ws_connections.load(Ordering::Relaxed),
            "Current WebSocket connections"
        );
        line!(
            "rohomieo_sessions_active",
            self.sessions_active.load(Ordering::Relaxed),
            "Active signaling sessions"
        );
        line!(
            "rohomieo_hosts_registered_total",
            self.hosts_registered.load(Ordering::Relaxed),
            "Total host registrations",
            counter
        );
        line!(
            "rohomieo_viewers_registered_total",
            self.viewers_registered.load(Ordering::Relaxed),
            "Total viewer registrations",
            counter
        );
        line!(
            "rohomieo_pin_failures_total",
            self.pin_failures.load(Ordering::Relaxed),
            "Failed PIN attempts",
            counter
        );
        line!(
            "rohomieo_relay_messages_total",
            self.relay_messages.load(Ordering::Relaxed),
            "SDP/ICE messages relayed",
            counter
        );
        line!(
            "rohomieo_sessions_expired_total",
            self.sessions_expired.load(Ordering::Relaxed),
            "Sessions removed by TTL sweeper",
            counter
        );
        out
    }
}

impl Default for Metrics {
    fn default() -> Self {
        Self::new()
    }
}
