mod session;
mod ws;

use anyhow::Context;
use axum::{
    extract::ws::WebSocketUpgrade,
    response::IntoResponse,
    routing::get,
    Router,
};
use clap::Parser;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls_pemfile::{certs, pkcs8_private_keys};
use session::SessionStore;
use std::{net::SocketAddr, path::PathBuf, sync::Arc};
use tower_http::{
    cors::{Any, CorsLayer},
    services::{ServeDir, ServeFile},
    trace::TraceLayer,
};
use tracing::info;

#[derive(Parser, Debug)]
#[command(name = "rohomieo-signaling", about = "Rohomieo signaling + static web server")]
struct Args {
    /// Bind address (use 0.0.0.0 for VPN/LAN access)
    #[arg(long, default_value = "0.0.0.0:8443")]
    bind: SocketAddr,

    /// Directory with built PWA (`web/dist`)
    #[arg(long, default_value = "../../web/dist")]
    web_root: PathBuf,

    /// TLS certificate PEM (optional; HTTP if omitted)
    #[arg(long)]
    cert: Option<PathBuf>,

    /// TLS private key PEM
    #[arg(long)]
    key: Option<PathBuf>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "rohomieo_signaling=info,tower_http=info".into()),
        )
        .init();

    let args = Args::parse();
    let store = Arc::new(SessionStore::new());

    let web_root = args.web_root.canonicalize().unwrap_or(args.web_root.clone());
    let index = web_root.join("index.html");
    let serve_dir = ServeDir::new(&web_root).not_found_service(ServeFile::new(index));

    let app = Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(|| async { "ok" }))
        .nest_service("/", serve_dir)
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(store);

    info!("Rohomieo signaling on {}", args.bind);
    info!("Web root: {}", web_root.display());

    match (args.cert, args.key) {
        (Some(cert_path), Some(key_path)) => {
            let cert = load_certs(&cert_path)?;
            let key = load_key(&key_path)?;
            let cfg = rustls::ServerConfig::builder()
                .with_no_client_auth()
                .with_single_cert(cert, key)?;
            let tls = axum_server::tls_rustls::RustlsConfig::from_config(Arc::new(cfg));
            axum_server::bind_rustls(args.bind, tls)
                .serve(app.into_make_service())
                .await?;
        }
        _ => {
            info!("TLS not configured — use only over WireGuard or trusted LAN");
            let listener = tokio::net::TcpListener::bind(args.bind).await?;
            axum::serve(listener, app).await?;
        }
    }

    Ok(())
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    axum::extract::State(store): axum::extract::State<Arc<SessionStore>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| ws::handle_socket(socket, store))
}

fn load_certs(path: &PathBuf) -> anyhow::Result<Vec<CertificateDer<'static>>> {
    let file = std::fs::File::open(path).context("open cert")?;
    let mut reader = std::io::BufReader::new(file);
    certs(&mut reader)
        .map(|c| c.map_err(anyhow::Error::from))
        .collect::<Result<Vec<_>, _>>()
        .context("parse cert")
}

fn load_key(path: &PathBuf) -> anyhow::Result<PrivateKeyDer<'static>> {
    let file = std::fs::File::open(path).context("open key")?;
    let mut reader = std::io::BufReader::new(file);
    let keys: Vec<_> = pkcs8_private_keys(&mut reader)
        .collect::<Result<Vec<_>, _>>()
        .context("parse key")?;
    let key = keys.into_iter().next().context("no private key in file")?;
    Ok(PrivateKeyDer::Pkcs8(key))
}
