mod capture;
mod encode;
mod input;
mod motion;
mod platform;
mod signaling_client;
mod webrtc_peer;

use anyhow::Result;
use clap::Parser;
use rand::Rng;
use signaling_client::SignalingClient;
use std::sync::Arc;
use tracing::info;

#[derive(Parser, Debug)]
#[command(name = "rohomieo-host", about = "Rohomieo remote desktop host agent")]
struct Args {
    /// WebSocket signaling URL (ws:// or wss://)
    #[arg(long, default_value = "ws://127.0.0.1:8443/ws")]
    signaling: String,

    /// Session ID (share with viewer); random UUID if omitted
    #[arg(long)]
    session: Option<String>,

    /// 6-digit PIN; random if omitted
    #[arg(long)]
    pin: Option<String>,

    #[arg(long, default_value = "My Laptop")]
    device_name: String,

    #[arg(long, default_value = "30")]
    fps: u32,

    #[arg(long, default_value = "8")]
    idle_fps: u32,
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

    let args = Args::parse();
    let session_id = args
        .session
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let pin = args.pin.unwrap_or_else(|| gen_pin());

    info!("═══════════════════════════════════════");
    info!("  Rohomieo host");
    info!("  Session: {}", session_id);
    info!("  PIN:     {}", pin);
    info!("  Connect viewer with same session + PIN");
    info!("═══════════════════════════════════════");

    let client = SignalingClient::connect(
        &args.signaling,
        session_id,
        pin,
        Some(args.device_name),
    )
    .await?;

    let signaling = Arc::new(client);
    webrtc_peer::run_session(signaling, args.fps, args.idle_fps).await
}

fn gen_pin() -> String {
    let n: u32 = rand::thread_rng().gen_range(100_000..999_999);
    format!("{n:06}")
}
