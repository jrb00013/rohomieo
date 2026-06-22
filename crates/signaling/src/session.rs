use crate::audit::{AuditEventKind, AuditLog};
use crate::metrics::Metrics;
use chrono::{DateTime, Utc};
use dashmap::DashMap;
use rohomieo_proto::Role;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;

pub type WsSender = mpsc::UnboundedSender<String>;

pub struct PeerSlot {
    pub tx: Option<WsSender>,
}

pub struct Session {
    pub pin: String,
    pub device_name: Option<String>,
    pub host: PeerSlot,
    pub viewer: PeerSlot,
    pub pin_failures: u32,
    pub locked_until: Option<DateTime<Utc>>,
    pub last_activity: DateTime<Utc>,
}

pub struct SessionStore {
    sessions: DashMap<String, Session>,
    connections: AtomicUsize,
    audit: Arc<AuditLog>,
    metrics: Arc<Metrics>,
    max_pin_failures: u32,
    session_ttl: Duration,
}

impl SessionStore {
    pub fn new(audit: Arc<AuditLog>, metrics: Arc<Metrics>) -> Self {
        Self {
            sessions: DashMap::new(),
            connections: AtomicUsize::new(0),
            audit,
            metrics,
            max_pin_failures: 5,
            session_ttl: Duration::from_secs(3600),
        }
    }

    pub fn with_limits(
        audit: Arc<AuditLog>,
        metrics: Arc<Metrics>,
        max_pin_failures: u32,
        session_ttl_secs: u64,
    ) -> Self {
        Self {
            sessions: DashMap::new(),
            connections: AtomicUsize::new(0),
            audit,
            metrics,
            max_pin_failures,
            session_ttl: Duration::from_secs(session_ttl_secs),
        }
    }

    pub fn metrics(&self) -> Arc<Metrics> {
        Arc::clone(&self.metrics)
    }

    pub fn audit(&self) -> Arc<AuditLog> {
        Arc::clone(&self.audit)
    }

    pub fn connection_count(&self) -> usize {
        self.connections.load(Ordering::Relaxed)
    }

    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }

    fn touch(&self, session_id: &str) {
        if let Some(mut s) = self.sessions.get_mut(session_id) {
            s.last_activity = Utc::now();
        }
    }

    fn check_pin_lock(entry: &Session) -> Result<(), String> {
        if let Some(until) = entry.locked_until {
            if Utc::now() < until {
                return Err("too many failed PIN attempts — try again in a few minutes".into());
            }
        }
        Ok(())
    }

    fn record_pin_failure(&self, session_id: &str) {
        if let Some(mut entry) = self.sessions.get_mut(session_id) {
            entry.pin_failures += 1;
            self.metrics.pin_failures.fetch_add(1, Ordering::Relaxed);
            self.audit.record(
                session_id,
                AuditEventKind::PinFailure,
                None,
                Some(format!("attempt {}", entry.pin_failures)),
            );
            if entry.pin_failures >= self.max_pin_failures {
                entry.locked_until = Some(Utc::now() + chrono::Duration::minutes(5));
                entry.pin_failures = 0;
            }
        }
    }

    pub fn register_host(
        &self,
        session_id: String,
        pin: String,
        device_name: Option<String>,
        tx: WsSender,
    ) -> Result<(), String> {
        let mut entry = self.sessions.entry(session_id.clone()).or_insert_with(|| {
            self.metrics
                .sessions_active
                .fetch_add(1, Ordering::Relaxed);
            Session {
                pin: pin.clone(),
                device_name: device_name.clone(),
                host: PeerSlot { tx: None },
                viewer: PeerSlot { tx: None },
                pin_failures: 0,
                locked_until: None,
                last_activity: Utc::now(),
            }
        });

        Self::check_pin_lock(&entry)?;
        if entry.pin != pin {
            drop(entry);
            self.record_pin_failure(&session_id);
            return Err("invalid PIN for session".into());
        }
        if entry.device_name.is_none() {
            entry.device_name = device_name;
        }
        entry.host.tx = Some(tx);
        entry.last_activity = Utc::now();
        self.metrics
            .hosts_registered
            .fetch_add(1, Ordering::Relaxed);
        self.audit.record(
            &session_id,
            AuditEventKind::HostRegistered,
            Some(Role::Host),
            None,
        );
        Ok(())
    }

    pub fn register_viewer(
        &self,
        session_id: String,
        pin: String,
        tx: WsSender,
    ) -> Result<(), String> {
        let mut entry = self
            .sessions
            .get_mut(&session_id)
            .ok_or_else(|| {
                self.audit.record(
                    &session_id,
                    AuditEventKind::ViewerRejected,
                    Some(Role::Viewer),
                    Some("session not found".into()),
                );
                "session not found — the host is not connected to signaling yet. \
                 On the laptop, check the host window: it must show \"session is live\". \
                 If you see a WebSocket error, restart with run-bridge.ps1 (host needs wss:// when the page uses https://)."
                    .to_string()
            })?;

        Self::check_pin_lock(&entry)?;
        if entry.pin != pin {
            let sid = session_id.clone();
            drop(entry);
            self.record_pin_failure(&sid);
            self.audit.record(
                &sid,
                AuditEventKind::ViewerRejected,
                Some(Role::Viewer),
                Some("invalid PIN".into()),
            );
            return Err("invalid PIN".into());
        }
        entry.viewer.tx = Some(tx);
        entry.last_activity = Utc::now();
        self.metrics
            .viewers_registered
            .fetch_add(1, Ordering::Relaxed);
        self.audit.record(
            &session_id,
            AuditEventKind::ViewerRegistered,
            Some(Role::Viewer),
            None,
        );
        Ok(())
    }

    pub fn peer_tx(&self, session_id: &str, role: Role) -> Option<WsSender> {
        self.sessions.get(session_id).and_then(|s| match role {
            Role::Host => s.host.tx.clone(),
            Role::Viewer => s.viewer.tx.clone(),
        })
    }

    pub fn other_role(role: Role) -> Role {
        match role {
            Role::Host => Role::Viewer,
            Role::Viewer => Role::Host,
        }
    }

    pub fn relay(&self, session_id: &str, from: Role, payload: String) {
        self.touch(session_id);
        self.metrics.relay_messages.fetch_add(1, Ordering::Relaxed);
        if let Some(tx) = self.peer_tx(session_id, Self::other_role(from)) {
            let _ = tx.send(payload);
        }
    }

    pub fn disconnect(&self, session_id: &str, role: Role) {
        let kind = match role {
            Role::Host => AuditEventKind::HostDisconnected,
            Role::Viewer => AuditEventKind::ViewerDisconnected,
        };
        self.audit
            .record(session_id, kind, Some(role), None);

        if let Some(mut s) = self.sessions.get_mut(session_id) {
            match role {
                Role::Host => s.host.tx = None,
                Role::Viewer => s.viewer.tx = None,
            }
            if s.host.tx.is_none() && s.viewer.tx.is_none() {
                drop(s);
                self.sessions.remove(session_id);
                self.metrics
                    .sessions_active
                    .fetch_sub(1, Ordering::Relaxed);
            }
        }
    }

    pub fn inc_conn(&self) {
        self.connections.fetch_add(1, Ordering::Relaxed);
        self.metrics
            .ws_connections
            .fetch_add(1, Ordering::Relaxed);
    }

    pub fn dec_conn(&self) {
        self.connections.fetch_sub(1, Ordering::Relaxed);
        self.metrics
            .ws_connections
            .fetch_sub(1, Ordering::Relaxed);
    }

    /// Remove sessions with no peers that exceeded TTL.
    pub fn sweep_stale(&self) -> usize {
        let cutoff = Utc::now() - chrono::Duration::from_std(self.session_ttl).unwrap_or_default();
        let mut removed = 0usize;
        self.sessions.retain(|id, s| {
            let empty = s.host.tx.is_none() && s.viewer.tx.is_none();
            let stale = s.last_activity < cutoff;
            if empty && stale {
                self.audit.record(
                    id,
                    AuditEventKind::SessionExpired,
                    None,
                    Some("TTL exceeded".into()),
                );
                self.metrics
                    .sessions_expired
                    .fetch_add(1, Ordering::Relaxed);
                self.metrics
                    .sessions_active
                    .fetch_sub(1, Ordering::Relaxed);
                removed += 1;
                false
            } else {
                true
            }
        });
        removed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> SessionStore {
        SessionStore::with_limits(Arc::new(AuditLog::new()), Arc::new(Metrics::new()), 3, 60)
    }

    fn dummy_tx() -> WsSender {
        let (tx, _rx) = mpsc::unbounded_channel();
        tx
    }

    #[test]
    fn pin_lockout_after_failures() {
        let s = store();
        let sid = "test-session".to_string();
        s.register_host(sid.clone(), "123456".into(), None, dummy_tx())
            .unwrap();
        for _ in 0..3 {
            let _ = s.register_viewer(sid.clone(), "000000".into(), dummy_tx());
        }
        let err = s
            .register_viewer(sid.clone(), "123456".into(), dummy_tx())
            .unwrap_err();
        assert!(err.contains("too many failed"));
    }
}
