use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use rohomieo_proto::{Role, SignalMessage};
use tokio::sync::mpsc;
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{info, warn};
use url::Url;

pub enum SignalingEvent {
    PeerJoined,
    PeerLeft,
    Offer(String),
    Answer(String),
    IceCandidate {
        candidate: String,
        sdp_mid: Option<String>,
        sdp_mline_index: Option<u16>,
    },
    Error(String),
}

pub struct SignalingClient {
    pub tx: mpsc::UnboundedSender<SignalMessage>,
    rx: tokio::sync::Mutex<mpsc::UnboundedReceiver<SignalingEvent>>,
}

impl SignalingClient {
    pub async fn recv(&self) -> Option<SignalingEvent> {
        self.rx.lock().await.recv().await
    }
}

impl SignalingClient {
    pub async fn connect(
        signaling_url: &str,
        session_id: String,
        pin: String,
        device_name: Option<String>,
    ) -> Result<Self> {
        let url = Url::parse(signaling_url).context("parse signaling URL")?;
        let (ws, _) = connect_async(url.as_str())
            .await
            .context("websocket connect")?;
        let (mut write, mut read) = ws.split();

        let (out_tx, mut out_rx) = mpsc::unbounded_channel::<SignalMessage>();
        let (evt_tx, evt_rx) = mpsc::unbounded_channel::<SignalingEvent>();
        let out_for_read = out_tx.clone();

        out_tx
            .send(SignalMessage::RegisterHost {
                session_id: session_id.clone(),
                pin,
                device_name,
            })
            .unwrap();

        tokio::spawn(async move {
            while let Some(msg) = out_rx.recv().await {
                if let Ok(json) = msg.to_json() {
                    if write.send(Message::Text(json.into())).await.is_err() {
                        break;
                    }
                }
            }
        });

        let sid = session_id.clone();
        tokio::spawn(async move {
            while let Some(Ok(Message::Text(text))) = read.next().await {
                let msg = match SignalMessage::from_json(&text) {
                    Ok(m) => m,
                    Err(e) => {
                        warn!("signaling parse: {e}");
                        continue;
                    }
                };
                match msg {
                    SignalMessage::Registered { role, session_id: s } => {
                        info!("registered as {:?} session {}", role, s);
                    }
                    SignalMessage::PeerJoined { role } => {
                        if role == Role::Viewer {
                            let _ = evt_tx.send(SignalingEvent::PeerJoined);
                        }
                    }
                    SignalMessage::PeerLeft => {
                        let _ = evt_tx.send(SignalingEvent::PeerLeft);
                    }
                    SignalMessage::Offer { sdp } => {
                        let _ = evt_tx.send(SignalingEvent::Offer(sdp));
                    }
                    SignalMessage::Answer { sdp } => {
                        let _ = evt_tx.send(SignalingEvent::Answer(sdp));
                    }
                    SignalMessage::IceCandidate {
                        candidate,
                        sdp_mid,
                        sdp_mline_index,
                    } => {
                        let _ = evt_tx.send(SignalingEvent::IceCandidate {
                            candidate,
                            sdp_mid,
                            sdp_mline_index,
                        });
                    }
                    SignalMessage::Error { message } => {
                        let _ = evt_tx.send(SignalingEvent::Error(message));
                    }
                    SignalMessage::Heartbeat => {
                        let _ = out_for_read.send(SignalMessage::Heartbeat);
                    }
                    _ => {}
                }
            }
            let _ = sid;
        });

        Ok(Self {
            tx: out_tx,
            rx: tokio::sync::Mutex::new(evt_rx),
        })
    }

    pub fn send(&self, msg: SignalMessage) {
        let _ = self.tx.send(msg);
    }
}
