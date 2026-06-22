//! JSON wire protocol shared by signaling, host, web, and mobile clients.

use serde::{Deserialize, Serialize};

/// Top-level WebSocket envelope.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum SignalMessage {
    RegisterHost {
        session_id: String,
        pin: String,
        device_name: Option<String>,
    },
    RegisterViewer {
        session_id: String,
        pin: String,
    },
    Registered {
        role: Role,
        session_id: String,
    },
    Error {
        message: String,
    },
    Offer {
        sdp: String,
    },
    Answer {
        sdp: String,
    },
    IceCandidate {
        candidate: String,
        #[serde(rename = "sdpMid")]
        sdp_mid: Option<String>,
        #[serde(rename = "sdpMLineIndex")]
        sdp_mline_index: Option<u16>,
    },
    Heartbeat,
    Pong,
    PeerJoined {
        role: Role,
    },
    PeerLeft,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    Host,
    Viewer,
}

/// Input events sent over WebRTC DataChannel (host ← viewer).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum InputEvent {
    Pointer {
        /// Normalized 0.0–1.0
        x: f64,
        y: f64,
        /// 0 = move, 1 = left down, 2 = left up, 3 = right down, 4 = right up
        action: u8,
    },
    Key {
        key: String,
        down: bool,
    },
    Wheel {
        delta_x: f64,
        delta_y: f64,
    },
}

/// Optional cursor overlay when video is throttled.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CursorOverlay {
    pub x: f64,
    pub y: f64,
}

impl SignalMessage {
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    pub fn from_json(s: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(s)
    }
}

impl InputEvent {
    pub fn from_json(s: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_register_host() {
        let msg = SignalMessage::RegisterHost {
            session_id: "abc".into(),
            pin: "123456".into(),
            device_name: Some("desk".into()),
        };
        let json = msg.to_json().unwrap();
        let back = SignalMessage::from_json(&json).unwrap();
        assert!(matches!(back, SignalMessage::RegisterHost { .. }));
    }

    #[test]
    fn roundtrip_wheel_input() {
        let evt = InputEvent::Wheel {
            delta_x: 0.0,
            delta_y: -120.0,
        };
        let json = serde_json::to_string(&evt).unwrap();
        let back = InputEvent::from_json(&json).unwrap();
        assert!(matches!(back, InputEvent::Wheel { delta_y, .. } if delta_y == -120.0));
    }

    #[test]
    fn role_snake_case() {
        let json = r#"{"type":"registered","role":"viewer","session_id":"x"}"#;
        let msg = SignalMessage::from_json(json).unwrap();
        assert!(matches!(msg, SignalMessage::Registered { role: Role::Viewer, .. }));
    }
}
