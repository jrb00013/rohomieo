use dashmap::DashMap;
use rohomieo_proto::Role;
use std::sync::atomic::{AtomicUsize, Ordering};
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
}

pub struct SessionStore {
    sessions: DashMap<String, Session>,
    connections: AtomicUsize,
}

impl SessionStore {
    pub fn new() -> Self {
        Self {
            sessions: DashMap::new(),
            connections: AtomicUsize::new(0),
        }
    }

    pub fn connection_count(&self) -> usize {
        self.connections.load(Ordering::Relaxed)
    }

    pub fn register_host(
        &self,
        session_id: String,
        pin: String,
        device_name: Option<String>,
        tx: WsSender,
    ) -> Result<(), String> {
        let mut entry = self.sessions.entry(session_id.clone()).or_insert_with(|| Session {
            pin: pin.clone(),
            device_name: device_name.clone(),
            host: PeerSlot { tx: None },
            viewer: PeerSlot { tx: None },
        });

        if entry.pin != pin {
            return Err("invalid PIN for session".into());
        }
        if entry.device_name.is_none() {
            entry.device_name = device_name;
        }
        entry.host.tx = Some(tx);
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
                "session not found — the host is not connected to signaling yet. \
                 On the laptop, check the host window: it must show \"session is live\". \
                 If you see a WebSocket error, restart with run-bridge.ps1 (host needs wss:// when the page uses https://)."
                    .to_string()
            })?;

        if entry.pin != pin {
            return Err("invalid PIN".into());
        }
        entry.viewer.tx = Some(tx);
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
        if let Some(tx) = self.peer_tx(session_id, Self::other_role(from)) {
            let _ = tx.send(payload);
        }
    }

    pub fn disconnect(&self, session_id: &str, role: Role) {
        if let Some(mut s) = self.sessions.get_mut(session_id) {
            match role {
                Role::Host => s.host.tx = None,
                Role::Viewer => s.viewer.tx = None,
            }
            if s.host.tx.is_none() && s.viewer.tx.is_none() {
                drop(s);
                self.sessions.remove(session_id);
            }
        }
    }

    pub fn inc_conn(&self) {
        self.connections.fetch_add(1, Ordering::Relaxed);
    }

    pub fn dec_conn(&self) {
        self.connections.fetch_sub(1, Ordering::Relaxed);
    }
}
