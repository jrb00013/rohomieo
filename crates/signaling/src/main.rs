mod api;
mod audit;
mod metrics;
mod session;
mod ws;

use anyhow::Context;
use api::{api_audit, api_status, metrics_handler};
use audit::AuditLog;
use axum::{
    extract::{ws::WebSocketUpgrade, State},
    response::IntoResponse,
    routing::get,
    Router,
};
use clap::Parser;
use metrics::Metrics;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls_pemfile::{certs, pkcs8_private_keys};
use session::SessionStore;
use std::{net::SocketAddr, path::PathBuf, sync::Arc, time::Duration};
use tower_http::{
    cors::{Any, CorsLayer},
    services::{ServeDir, ServeFile},
    trace::TraceLayer,
};
use tracing::info;

#[derive(Clone)]
struct AppState {
    store: Arc<SessionStore>,
    audit: Arc<AuditLog>,
}

#[derive(Parser, Debug)]
#[command(name = "rohomieo-signaling", about = "Rohomieo signaling + static web server", version)]
struct Args {
    /// Bind address (use 0.0.0.0 for VPN/LAN access)
    #[arg(long, default_value = "0.0.0.0:8443", env = "ROHOMIEO_BIND")]
    bind: SocketAddr,

    /// Directory with built PWA (`web/dist`)
    #[arg(long, default_value = "../../web/dist")]
    web_root: PathBuf,

    /// TLS certificate PEM (optional; HTTP if omitted)
    #[arg(long, env = "ROHOMIEO_CERT")]
    cert: Option<PathBuf>,

    /// TLS private key PEM
    #[arg(long, env = "ROHOMIEO_KEY")]
    key: Option<PathBuf>,

    /// Remove stale sessions after this many seconds of inactivity
    #[arg(long, default_value = "3600", env = "ROHOMIEO_SESSION_TTL_SECS")]
    session_ttl_secs: u64,

    /// Lock session after this many failed PIN attempts
    #[arg(long, default_value = "5", env = "ROHOMIEO_MAX_PIN_FAILURES")]
    max_pin_failures: u32,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = rustls::crypto::ring::default_provider().install_default();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "rohomieo_signaling=info,tower_http=info".into()),
        )
        .init();

    let args = Args::parse();
    let audit = Arc::new(AuditLog::new());
    let metrics = Arc::new(Metrics::new());
    let store = Arc::new(SessionStore::with_limits(
        Arc::clone(&audit),
        Arc::clone(&metrics),
        args.max_pin_failures,
        args.session_ttl_secs,
    ));

    let state = AppState {
        store: Arc::clone(&store),
        audit: Arc::clone(&audit),
    };

    spawn_ttl_sweeper(Arc::clone(&store));

    let web_root = args.web_root.canonicalize().unwrap_or(args.web_root.clone());
    let index = web_root.join("index.html");
    let serve_dir = ServeDir::new(&web_root).not_found_service(ServeFile::new(index));

    let app = Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(health_legacy))
        .route("/api/status", get(api_status))
        .route("/api/audit", get(api_audit))
        .route("/metrics", get(metrics_handler))
        .nest_service("/", serve_dir)
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    info!("Rohomieo signaling v{} on {}", env!("CARGO_PKG_VERSION"), args.bind);
    info!("Web root: {}", web_root.display());
    info!(
        "Endpoints: /ws /health /api/status /api/audit /metrics"
    );

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

fn spawn_ttl_sweeper(store: Arc<SessionStore>) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(300));
        loop {
            interval.tick().await;
            let n = store.sweep_stale();
            if n > 0 {
                tracing::debug!("swept {n} stale sessions");
            }
        }
    });
}

async fn health_legacy(State(state): State<AppState>) -> impl IntoResponse {
    format!(
        "ok version={} ws_connections={} sessions={}",
        env!("CARGO_PKG_VERSION"),
        state.store.connection_count(),
        state.store.session_count()
    )
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| ws::handle_socket(socket, state.store))
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
