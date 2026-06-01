use crate::session::SessionStore;
use axum::extract::ws::{Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use rohomieo_proto::{Role, SignalMessage};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{debug, warn};

pub async fn handle_socket(socket: WebSocket, store: Arc<SessionStore>) {
    store.inc_conn();
    let (sender, mut receiver) = socket.split();
    let sender = Arc::new(Mutex::new(sender));
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();

    let sender_fwd = Arc::clone(&sender);
    let forward = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            let mut s = sender_fwd.lock().await;
            if s.send(Message::Text(msg.into())).await.is_err() {
                break;
            }
        }
    });

    let mut session_id: Option<String> = None;
    let mut role: Option<Role> = None;

    while let Some(Ok(msg)) = receiver.next().await {
        let text = match msg {
            Message::Text(t) => t.to_string(),
            Message::Ping(p) => {
                let mut s = sender.lock().await;
                let _ = s.send(Message::Pong(p)).await;
                continue;
            }
            Message::Close(_) => break,
            _ => continue,
        };

        let parsed: SignalMessage = match SignalMessage::from_json(&text) {
            Ok(m) => m,
            Err(e) => {
                warn!("bad json: {e}");
                send_error(&tx, &format!("invalid message: {e}"));
                continue;
            }
        };

        match parsed {
            SignalMessage::RegisterHost {
                session_id: sid,
                pin,
                device_name,
            } => {
                if let Err(e) = store.register_host(sid.clone(), pin, device_name, tx.clone()) {
                    send_error(&tx, &e);
                    continue;
                }
                session_id = Some(sid.clone());
                role = Some(Role::Host);
                let _ = tx.send(
                    SignalMessage::Registered {
                        role: Role::Host,
                        session_id: sid,
                    }
                    .to_json()
                    .unwrap(),
                );
                debug!("host registered");
            }
            SignalMessage::RegisterViewer {
                session_id: sid,
                pin,
            } => {
                if let Err(e) = store.register_viewer(sid.clone(), pin, tx.clone()) {
                    send_error(&tx, &e);
                    continue;
                }
                session_id = Some(sid.clone());
                role = Some(Role::Viewer);
                let _ = tx.send(
                    SignalMessage::Registered {
                        role: Role::Viewer,
                        session_id: sid.clone(),
                    }
                    .to_json()
                    .unwrap(),
                );
                // Notify host that viewer joined
                if let Some(host_tx) = store.peer_tx(&sid, Role::Host) {
                    let _ = host_tx.send(
                        SignalMessage::PeerJoined {
                            role: Role::Viewer,
                        }
                        .to_json()
                        .unwrap(),
                    );
                }
                debug!("viewer registered");
            }
            SignalMessage::Heartbeat => {
                let _ = tx.send(SignalMessage::Pong.to_json().unwrap());
            }
            SignalMessage::Offer { .. }
            | SignalMessage::Answer { .. }
            | SignalMessage::IceCandidate { .. } => {
                if let (Some(sid), Some(r)) = (&session_id, role) {
                    store.relay(sid, r, text);
                }
            }
            _ => {}
        }
    }

    if let (Some(sid), Some(r)) = (session_id, role) {
        store.disconnect(&sid, r);
        store.relay(
            &sid,
            r,
            SignalMessage::PeerLeft.to_json().unwrap_or_default(),
        );
    }

    forward.abort();
    store.dec_conn();
}

fn send_error(tx: &tokio::sync::mpsc::UnboundedSender<String>, message: &str) {
    let _ = tx.send(
        SignalMessage::Error {
            message: message.to_string(),
        }
        .to_json()
        .unwrap_or_default(),
    );
}
