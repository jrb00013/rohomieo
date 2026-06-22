//! Connection audit log — records host/viewer lifecycle events for ops and security review.

use chrono::{DateTime, Utc};
use rohomieo_proto::Role;
use serde::Serialize;
use std::collections::VecDeque;
use std::sync::Mutex;

const DEFAULT_CAPACITY: usize = 500;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AuditEventKind {
    HostRegistered,
    ViewerRegistered,
    ViewerRejected,
    HostDisconnected,
    ViewerDisconnected,
    PinFailure,
    SessionExpired,
}

#[derive(Debug, Clone, Serialize)]
pub struct AuditEntry {
    pub ts: DateTime<Utc>,
    pub session_id: String,
    pub kind: AuditEventKind,
    pub detail: Option<String>,
    pub role: Option<Role>,
}

pub struct AuditLog {
    entries: Mutex<VecDeque<AuditEntry>>,
    capacity: usize,
}

impl AuditLog {
    pub fn new() -> Self {
        Self::with_capacity(DEFAULT_CAPACITY)
    }

    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            entries: Mutex::new(VecDeque::with_capacity(capacity.min(10_000))),
            capacity,
        }
    }

    pub fn record(
        &self,
        session_id: impl Into<String>,
        kind: AuditEventKind,
        role: Option<Role>,
        detail: Option<String>,
    ) {
        let entry = AuditEntry {
            ts: Utc::now(),
            session_id: session_id.into(),
            kind,
            detail,
            role,
        };
        let mut buf = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        if buf.len() >= self.capacity {
            buf.pop_front();
        }
        buf.push_back(entry);
    }

    pub fn recent(&self, limit: usize) -> Vec<AuditEntry> {
        let buf = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        let start = buf.len().saturating_sub(limit);
        buf.range(start..).cloned().collect()
    }

    pub fn len(&self) -> usize {
        self.entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .len()
    }
}

impl Default for AuditLog {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ring_buffer_drops_oldest() {
        let log = AuditLog::with_capacity(2);
        log.record("a", AuditEventKind::HostRegistered, Some(Role::Host), None);
        log.record("b", AuditEventKind::ViewerRegistered, Some(Role::Viewer), None);
        log.record("c", AuditEventKind::PinFailure, None, Some("bad pin".into()));
        let recent = log.recent(10);
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].session_id, "b");
        assert_eq!(recent[1].session_id, "c");
    }
}
