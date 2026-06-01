use anyhow::{bail, Context, Result};
use futures_util::{SinkExt, StreamExt};
use rohomieo_proto::{Role, SignalMessage};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::sync::oneshot;
use tokio_tungstenite::{
    connect_async, connect_async_tls_with_config, tungstenite::Message, Connector,
};
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
        let (ws, _) = connect_signaling(&url).await?;
        let (mut write, mut read) = ws.split();

        let (out_tx, mut out_rx) = mpsc::unbounded_channel::<SignalMessage>();
        let (evt_tx, evt_rx) = mpsc::unbounded_channel::<SignalingEvent>();
        let out_for_read = out_tx.clone();
        let (reg_tx, reg_rx) = oneshot::channel::<Result<(), String>>();

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
        let mut reg_tx = Some(reg_tx);
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
                        if let Some(tx) = reg_tx.take() {
                            let _ = tx.send(Ok(()));
                        }
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
                        if let Some(tx) = reg_tx.take() {
                            let _ = tx.send(Err(message.clone()));
                        }
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

        match tokio::time::timeout(Duration::from_secs(8), reg_rx).await {
            Ok(Ok(Ok(()))) => info!("signaling: session is live — viewer can connect now"),
            Ok(Ok(Err(msg))) => bail!("signaling rejected registration: {msg}"),
            Ok(Err(_)) => bail!("signaling closed before registration completed"),
            Err(_) => bail!(
                "timeout waiting for signaling registration — use wss://127.0.0.1:8443/ws when the server uses HTTPS/TLS"
            ),
        }

        Ok(Self {
            tx: out_tx,
            rx: tokio::sync::Mutex::new(evt_rx),
        })
    }

    pub fn send(&self, msg: SignalMessage) {
        let _ = self.tx.send(msg);
    }
}

async fn connect_signaling(
    url: &Url,
) -> Result<(
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
    tokio_tungstenite::tungstenite::handshake::client::Response,
)> {
    if url.scheme() == "wss" && url.host_str().is_some_and(is_loopback_host) {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let cfg = loopback_tls_config();
        let connector = Connector::Rustls(Arc::new(cfg));
        connect_async_tls_with_config(url.as_str(), None, false, Some(connector))
            .await
            .context("websocket connect (wss to localhost — accepts dev self-signed cert)")
    } else {
        connect_async(url.as_str())
            .await
            .context("websocket connect")
    }
}

fn is_loopback_host(host: &str) -> bool {
    matches!(host, "localhost" | "127.0.0.1" | "::1")
}

fn loopback_tls_config() -> rustls::ClientConfig {
    rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(InsecureLoopbackVerifier))
        .with_no_client_auth()
}

/// Dev-only: signaling serves a self-signed cert on localhost.
#[derive(Debug)]
struct InsecureLoopbackVerifier;

impl rustls::client::danger::ServerCertVerifier for InsecureLoopbackVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}
