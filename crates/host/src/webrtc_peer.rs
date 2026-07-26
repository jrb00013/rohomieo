use crate::capture::ScreenCapture;
use crate::encode::H264Encoder;
use crate::input::InputInjector;
use crate::invite;
use crate::jpeg_frame;
use crate::motion::MotionDetector;
use crate::signaling_client::{SignalingClient, SignalingEvent};
use crate::text_focus;
use anyhow::Result;
use bytes::Bytes;
use rohomieo_proto::{HostEvent, InputEvent, SignalMessage};
use std::net::IpAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{info, warn};
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::api::media_engine::{MediaEngine, MIME_TYPE_H264};
use webrtc::api::setting_engine::{SctpMaxMessageSize, SettingEngine};
use webrtc::api::APIBuilder;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::data_channel::data_channel_state::RTCDataChannelState;
use webrtc::data_channel::RTCDataChannel;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
use webrtc::ice_transport::ice_candidate_type::RTCIceCandidateType;
use webrtc::interceptor::registry::Registry;
use webrtc::media::Sample;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
use webrtc::track::track_local::TrackLocal;
use webrtc::ice::mdns::MulticastDnsMode;
use webrtc::ice::network_type::NetworkType;

pub struct WebRtcHost {
    pc: Arc<RTCPeerConnection>,
    video_track: Arc<TrackLocalStaticSample>,
    signaling: Arc<SignalingClient>,
    stream_video: Arc<AtomicBool>,
    capture_alive: Arc<AtomicBool>,
    video_dc: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
}

fn ice_iface_ok(name: &str) -> bool {
    let n = name.to_ascii_lowercase();
    !(n.contains("wsl")
        || n.contains("vethernet")
        || n.contains("hyper-v")
        || n.contains("docker")
        || n.contains("loopback")
        || n.contains("bluetooth")
        || n.contains("virtualbox")
        || n.contains("vmware")
        || n.starts_with("br-")
        || n.starts_with("veth")
        || n.starts_with("cali"))
}

fn ice_ip_ok(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            !v4.is_loopback()
                && !v4.is_link_local()
                && !v4.is_unspecified()
                && !v4.is_multicast()
                && !v4.is_broadcast()
        }
        // Phone ↔ Windows LAN path is IPv4; skip broken IPv6/APIPA-style noise on WSL hosts.
        IpAddr::V6(_) => false,
    }
}

fn ice_candidate_line_ok(candidate: &str) -> bool {
    // a=candidate:… foundation component protocol priority ip port typ …
    let parts: Vec<&str> = candidate.split_whitespace().collect();
    let ip = parts.get(4).copied().unwrap_or("");
    if ip.ends_with(".local") {
        return false;
    }
    match ip.parse::<IpAddr>() {
        Ok(addr) => ice_ip_ok(addr),
        Err(_) => false,
    }
}

impl WebRtcHost {
    pub async fn new(
        signaling: Arc<SignalingClient>,
        input_slot: Arc<Mutex<Option<InputInjector>>>,
    ) -> Result<Self> {
        let mut m = MediaEngine::default();
        m.register_default_codecs()?;

        let mut registry = Registry::new();
        registry = register_default_interceptors(registry, &mut m)?;

        let mut setting = SettingEngine::default();
        setting.set_network_types(vec![NetworkType::Udp4]);
        setting.set_ice_multicast_dns_mode(MulticastDnsMode::Disabled);
        setting.set_ice_timeouts(
            Some(Duration::from_secs(30)),
            Some(Duration::from_secs(60)),
            Some(Duration::from_secs(2)),
        );
        setting.set_interface_filter(Box::new(|name| ice_iface_ok(name)));
        setting.set_ip_filter(Box::new(|ip| ice_ip_ok(ip)));
        // High-res JPEG for phones can be ~150–220KiB; keep headroom under the SCTP cap.
        setting.set_sctp_max_message_size_can_send(SctpMaxMessageSize::Bounded(512 * 1024));
        if let Some(lan) = invite::guess_lan_ip() {
            info!("ICE host candidate pinned to LAN {lan}");
            setting.set_nat_1to1_ips(vec![lan.to_string()], RTCIceCandidateType::Host);
        }

        let api = APIBuilder::new()
            .with_setting_engine(setting)
            .with_media_engine(m)
            .with_interceptor_registry(registry)
            .build();

        let config = RTCConfiguration {
            ice_servers: vec![],
            ..Default::default()
        };

        let pc = Arc::new(api.new_peer_connection(config).await?);

        let video_track = Arc::new(TrackLocalStaticSample::new(
            RTCRtpCodecCapability {
                mime_type: MIME_TYPE_H264.to_owned(),
                clock_rate: 90_000,
                sdp_fmtp_line:
                    "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f"
                        .to_owned(),
                ..Default::default()
            },
            "video".to_owned(),
            "rohomieo".to_owned(),
        ));

        let rtp_sender = pc
            .add_track(Arc::clone(&video_track) as Arc<dyn TrackLocal + Send + Sync>)
            .await?;

        tokio::spawn(async move {
            let mut buf = vec![0u8; 1500];
            while rtp_sender.read(&mut buf).await.is_ok() {}
        });

        let signaling_ice = Arc::clone(&signaling);
        pc.on_ice_candidate(Box::new(move |c| {
            let signaling = Arc::clone(&signaling_ice);
            Box::pin(async move {
                if let Some(c) = c {
                    if let Ok(init) = c.to_json() {
                        if !ice_candidate_line_ok(&init.candidate) {
                            return;
                        }
                        signaling.send(SignalMessage::IceCandidate {
                            candidate: init.candidate,
                            sdp_mid: init.sdp_mid,
                            sdp_mline_index: init.sdp_mline_index,
                        });
                    }
                }
            })
        }));

        pc.on_peer_connection_state_change(Box::new(move |s: RTCPeerConnectionState| {
            info!("peer connection state: {:?}", s);
            Box::pin(async {})
        }));

        let input_dc = pc
            .create_data_channel(
                "input",
                Some(
                    webrtc::data_channel::data_channel_init::RTCDataChannelInit {
                        ordered: Some(true),
                        ..Default::default()
                    },
                ),
            )
            .await?;

        // MUST use the same slot the capture loop fills — a local empty Mutex
        // made every touch/key parse OK then get dropped (injector always None).
        let input_for_dc = Arc::clone(&input_slot);
        let text_focus_state = Arc::new(AtomicBool::new(false));
        let input_dc_out = Arc::clone(&input_dc);
        let focus_state_for_msg = Arc::clone(&text_focus_state);
        input_dc.on_open({
            let input_dc_out = Arc::clone(&input_dc_out);
            let text_focus_state = Arc::clone(&text_focus_state);
            Box::new(move || {
                info!("input datachannel open (touch/keyboard)");
                let input_dc_out = Arc::clone(&input_dc_out);
                let text_focus_state = Arc::clone(&text_focus_state);
                Box::pin(async move {
                    spawn_text_focus_poller(input_dc_out, text_focus_state);
                })
            })
        });
        input_dc.on_message(Box::new(move |msg: DataChannelMessage| {
            let input_for_dc = Arc::clone(&input_for_dc);
            let input_dc_out = Arc::clone(&input_dc_out);
            let focus_state_for_msg = Arc::clone(&focus_state_for_msg);
            Box::pin(async move {
                let text = String::from_utf8_lossy(&msg.data);
                match InputEvent::from_json(&text) {
                    Ok(evt) => {
                        let check_focus = matches!(
                            evt,
                            InputEvent::Pointer {
                                action: 1 | 2,
                                ..
                            }
                        );
                        {
                            let mut guard = input_for_dc.lock().await;
                            if let Some(inj) = guard.as_mut() {
                                inj.handle(evt);
                            } else {
                                warn!("input event before injector ready: {text}");
                            }
                        }
                        if check_focus {
                            probe_and_send_text_focus(
                                Arc::clone(&input_dc_out),
                                Arc::clone(&focus_state_for_msg),
                            )
                            .await;
                        }
                    }
                    Err(e) => warn!("bad input event ({e}): {text}"),
                }
            })
        }));

        let video_dc_slot: Arc<Mutex<Option<Arc<RTCDataChannel>>>> = Arc::new(Mutex::new(None));
        let jpeg_dc = pc
            .create_data_channel(
                "frames",
                Some(
                    webrtc::data_channel::data_channel_init::RTCDataChannelInit {
                        // Reliable: phones usually can't decode OpenH264 and depend on JPEG.
                        // Unreliable + max_retransmits=0 dropped large frames → black screen.
                        ordered: Some(true),
                        ..Default::default()
                    },
                ),
            )
            .await?;
        jpeg_dc.on_open(Box::new(|| {
            info!("frames datachannel open (JPEG fallback for phones)");
            Box::pin(async {})
        }));
        *video_dc_slot.lock().await = Some(jpeg_dc);

        let stream_video = Arc::new(AtomicBool::new(false));
        let capture_alive = Arc::new(AtomicBool::new(true));

        Ok(Self {
            pc,
            video_track,
            signaling,
            stream_video,
            capture_alive,
            video_dc: video_dc_slot,
        })
    }

    pub async fn create_and_send_offer(&self) -> Result<()> {
        let offer = self.pc.create_offer(None).await?;
        self.pc.set_local_description(offer.clone()).await?;
        self.signaling.send(SignalMessage::Offer { sdp: offer.sdp });
        Ok(())
    }

    pub async fn handle_answer(&self, sdp: String) -> Result<()> {
        let answer = RTCSessionDescription::answer(sdp)?;
        self.pc.set_remote_description(answer).await?;
        self.stream_video.store(true, Ordering::SeqCst);
        info!("WebRTC negotiated — starting screen stream");
        Ok(())
    }

    pub async fn add_ice_candidate(
        &self,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_mline_index: Option<u16>,
    ) -> Result<()> {
        let init = RTCIceCandidateInit {
            candidate,
            sdp_mid,
            sdp_mline_index,
            ..Default::default()
        };
        self.pc.add_ice_candidate(init).await?;
        Ok(())
    }

    pub fn spawn_capture_loop(
        &self,
        target_fps: u32,
        idle_fps: u32,
        input_slot: Arc<Mutex<Option<InputInjector>>>,
    ) {
        let video_track = Arc::clone(&self.video_track);
        let stream_video = Arc::clone(&self.stream_video);
        let capture_alive = Arc::clone(&self.capture_alive);
        let video_dc = Arc::clone(&self.video_dc);
        tokio::spawn(async move {
            if let Err(e) = run_capture_loop(
                video_track,
                stream_video,
                capture_alive,
                video_dc,
                target_fps,
                idle_fps,
                input_slot,
            )
            .await
            {
                warn!("capture loop ended: {e}");
            }
        });
    }
}

async fn run_capture_loop(
    video_track: Arc<TrackLocalStaticSample>,
    stream_video: Arc<AtomicBool>,
    capture_alive: Arc<AtomicBool>,
    video_dc: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
    target_fps: u32,
    idle_fps: u32,
    input_slot: Arc<Mutex<Option<InputInjector>>>,
) -> Result<()> {
    let mut cap = ScreenCapture::primary()?;
    let (w, h) = cap.dimensions();
    let mut stride = cap.stride();
    info!("screen capture {w}x{h} stride={stride}");

    {
        let mut guard = input_slot.lock().await;
        *guard = Some(InputInjector::new(w as i32, h as i32)?);
    }

    let mut motion = MotionDetector::new(w, h, stride);
    let mut encoder = H264Encoder::new(w as u32, h as u32)?;
    let frame_duration = Duration::from_millis(1000 / target_fps.max(1) as u64);
    // ~12 fps JPEG — LAN can carry high-q frames; phones rely on this path.
    let jpeg_interval = Duration::from_millis(83);
    let mut ticker = tokio::time::interval(frame_duration);
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut last_jpeg = tokio::time::Instant::now() - jpeg_interval;
    let mut heartbeat_ticks = 0u32;
    let mut h264_frames: u64 = 0;
    let mut jpeg_frames: u64 = 0;

    while capture_alive.load(Ordering::SeqCst) {
        ticker.tick().await;

        if !stream_video.load(Ordering::SeqCst) {
            continue;
        }

        let idle = motion.is_idle();
        let delay = cap.frame_delay(idle, target_fps, idle_fps);
        if delay > frame_duration {
            tokio::time::sleep(delay - frame_duration).await;
        }

        let Some(bgra) = cap.capture_frame().await? else {
            continue;
        };

        if bgra.len() / h.max(1) >= w * 4 {
            stride = bgra.len() / h.max(1);
        }

        heartbeat_ticks += 1;
        let force_hb = heartbeat_ticks % 50 == 0;
        let send_h264 = motion.should_encode(&bgra, force_hb);

        if send_h264 {
            match encoder.encode_bgra(&bgra, w, h, stride) {
                Ok(Some(h264)) => {
                    if video_track
                        .write_sample(&Sample {
                            data: Bytes::from(h264),
                            duration: frame_duration,
                            ..Default::default()
                        })
                        .await
                        .is_ok()
                    {
                        h264_frames += 1;
                    }
                }
                Ok(None) => {}
                Err(e) => warn!("encode frame: {e:#}"),
            }
        }

        if last_jpeg.elapsed() >= jpeg_interval {
            last_jpeg = tokio::time::Instant::now();
            match jpeg_frame::bgra_to_jpeg(&bgra, w, h, stride) {
                Ok(jpeg) => {
                    let dc = video_dc.lock().await.clone();
                    if let Some(dc) = dc {
                        if dc.ready_state() == RTCDataChannelState::Open {
                            let n = jpeg.len();
                            match dc.send(&Bytes::from(jpeg)).await {
                                Ok(_) => {
                                    jpeg_frames += 1;
                                    if jpeg_frames == 1 {
                                        info!("first JPEG frame sent ({n} bytes)");
                                    }
                                }
                                Err(e) => warn!("JPEG frame send failed ({n} bytes): {e}"),
                            }
                        }
                    }
                }
                Err(e) => warn!("JPEG encode failed: {e:#}"),
            }
        }

        if heartbeat_ticks % 150 == 0 {
            info!(
                "streaming: {} H.264 frames, {} JPEG frames sent",
                h264_frames, jpeg_frames
            );
        }
    }
    Ok(())
}

async fn send_host_event(dc: &RTCDataChannel, evt: HostEvent) {
    if dc.ready_state() != RTCDataChannelState::Open {
        return;
    }
    match evt.to_json() {
        Ok(json) => {
            if let Err(e) = dc.send_text(json).await {
                warn!("host event send failed: {e}");
            }
        }
        Err(e) => warn!("host event encode failed: {e}"),
    }
}

async fn probe_and_send_text_focus(dc: Arc<RTCDataChannel>, state: Arc<AtomicBool>) {
    // Focus/caret often appears a beat after the injected click.
    tokio::time::sleep(Duration::from_millis(45)).await;
    let focused = text_focus::is_text_input_focused();
    state.store(focused, Ordering::SeqCst);
    // Always notify after a tap so the phone can raise/dismiss soft keyboard.
    send_host_event(&dc, HostEvent::TextFocus { focused }).await;

    tokio::time::sleep(Duration::from_millis(120)).await;
    let focused2 = text_focus::is_text_input_focused();
    if focused2 != focused {
        state.store(focused2, Ordering::SeqCst);
        send_host_event(&dc, HostEvent::TextFocus { focused: focused2 }).await;
    }
}

fn spawn_text_focus_poller(dc: Arc<RTCDataChannel>, state: Arc<AtomicBool>) {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_millis(450)).await;
            if dc.ready_state() != RTCDataChannelState::Open {
                break;
            }
            let focused = text_focus::is_text_input_focused();
            let prev = state.swap(focused, Ordering::SeqCst);
            if prev != focused {
                send_host_event(&dc, HostEvent::TextFocus { focused }).await;
            }
        }
    });
}

pub async fn run_session(
    signaling: Arc<SignalingClient>,
    target_fps: u32,
    idle_fps: u32,
) -> Result<()> {
    // Fresh PeerConnection per viewer — reusing a Failed PC after phone
    // disconnect makes the next scan look "dead" even with a live QR.
    let mut host: Option<WebRtcHost> = None;
    let input_slot: Arc<Mutex<Option<InputInjector>>> = Arc::new(Mutex::new(None));

    while let Some(evt) = signaling.recv().await {
        match evt {
            SignalingEvent::PeerJoined => {
                if let Some(old) = host.take() {
                    old.stream_video.store(false, Ordering::SeqCst);
                    old.capture_alive.store(false, Ordering::SeqCst);
                    let _ = old.pc.close().await;
                }
                info!("viewer joined — new peer connection + offer");
                let h = WebRtcHost::new(Arc::clone(&signaling), Arc::clone(&input_slot)).await?;
                h.spawn_capture_loop(target_fps, idle_fps, Arc::clone(&input_slot));
                h.create_and_send_offer().await?;
                host = Some(h);
            }
            SignalingEvent::Answer(sdp) => {
                if let Some(h) = host.as_ref() {
                    h.handle_answer(sdp).await?;
                } else {
                    warn!("answer with no active peer connection");
                }
            }
            SignalingEvent::IceCandidate {
                candidate,
                sdp_mid,
                sdp_mline_index,
            } => {
                if let Some(h) = host.as_ref() {
                    h.add_ice_candidate(candidate, sdp_mid, sdp_mline_index)
                        .await?;
                }
            }
            SignalingEvent::PeerLeft => {
                info!("viewer disconnected");
                if let Some(h) = host.as_ref() {
                    h.stream_video.store(false, Ordering::SeqCst);
                }
            }
            SignalingEvent::Error(m) => {
                warn!("signaling error: {m}");
            }
            SignalingEvent::Offer(_) => {}
        }
    }
    Ok(())
}
