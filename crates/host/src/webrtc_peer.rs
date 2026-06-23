use crate::capture::ScreenCapture;
use crate::encode::H264Encoder;
use crate::input::InputInjector;
use crate::jpeg_frame;
use crate::motion::MotionDetector;
use crate::signaling_client::{SignalingClient, SignalingEvent};
use anyhow::Result;
use bytes::Bytes;
use rohomieo_proto::{InputEvent, SignalMessage};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{info, warn};
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::api::media_engine::{MediaEngine, MIME_TYPE_H264};
use webrtc::api::APIBuilder;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::data_channel::data_channel_state::RTCDataChannelState;
use webrtc::data_channel::RTCDataChannel;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
use webrtc::interceptor::registry::Registry;
use webrtc::media::Sample;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
use webrtc::track::track_local::TrackLocal;

pub struct WebRtcHost {
    pc: Arc<RTCPeerConnection>,
    video_track: Arc<TrackLocalStaticSample>,
    signaling: Arc<SignalingClient>,
    stream_video: Arc<AtomicBool>,
    video_dc: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
}

impl WebRtcHost {
    pub async fn new(signaling: Arc<SignalingClient>) -> Result<Self> {
        let mut m = MediaEngine::default();
        m.register_default_codecs()?;

        let mut registry = Registry::new();
        registry = register_default_interceptors(registry, &mut m)?;

        let api = APIBuilder::new()
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

        let input_slot: Arc<Mutex<Option<InputInjector>>> = Arc::new(Mutex::new(None));

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

        let input_for_dc = Arc::clone(&input_slot);
        input_dc.on_message(Box::new(move |msg: DataChannelMessage| {
            let input_for_dc = Arc::clone(&input_for_dc);
            Box::pin(async move {
                if let Ok(evt) = InputEvent::from_json(&String::from_utf8_lossy(&msg.data)) {
                    if let Some(inj) = input_for_dc.lock().await.as_mut() {
                        inj.handle(evt);
                    }
                }
            })
        }));

        let video_dc_slot: Arc<Mutex<Option<Arc<RTCDataChannel>>>> = Arc::new(Mutex::new(None));
        let jpeg_dc = pc
            .create_data_channel(
                "frames",
                Some(
                    webrtc::data_channel::data_channel_init::RTCDataChannelInit {
                        ordered: Some(false),
                        max_retransmits: Some(0),
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

        Ok(Self {
            pc,
            video_track,
            signaling,
            stream_video,
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
        let video_dc = Arc::clone(&self.video_dc);
        tokio::spawn(async move {
            if let Err(e) = run_capture_loop(
                video_track,
                stream_video,
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
    video_dc: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
    target_fps: u32,
    idle_fps: u32,
    input_slot: Arc<Mutex<Option<InputInjector>>>,
) -> Result<()> {
    let mut cap = ScreenCapture::primary()?;
    let (w, h) = cap.dimensions();
    let mut stride = cap.stride();

    {
        let mut guard = input_slot.lock().await;
        *guard = Some(InputInjector::new(w as i32, h as i32)?);
    }

    let mut motion = MotionDetector::new(w, h, stride);
    let mut encoder = H264Encoder::new(w as u32, h as u32)?;
    let frame_duration = Duration::from_millis(1000 / target_fps.max(1) as u64);
    let jpeg_interval = Duration::from_millis(100); // 10 fps fallback
    let mut ticker = tokio::time::interval(frame_duration);
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut last_jpeg = tokio::time::Instant::now() - jpeg_interval;
    let mut heartbeat_ticks = 0u32;
    let mut h264_frames: u64 = 0;
    let mut jpeg_frames: u64 = 0;

    loop {
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
            if let Ok(jpeg) = jpeg_frame::bgra_to_jpeg(&bgra, w, h, stride) {
                let dc = video_dc.lock().await.clone();
                if let Some(dc) = dc {
                    if dc.ready_state() == RTCDataChannelState::Open
                        && dc.send(&Bytes::from(jpeg)).await.is_ok()
                    {
                        jpeg_frames += 1;
                    }
                }
            }
        }

        if heartbeat_ticks % 150 == 0 {
            info!(
                "streaming: {} H.264 frames, {} JPEG frames sent",
                h264_frames, jpeg_frames
            );
        }
    }
}

pub async fn run_session(
    signaling: Arc<SignalingClient>,
    target_fps: u32,
    idle_fps: u32,
) -> Result<()> {
    let host = WebRtcHost::new(Arc::clone(&signaling)).await?;
    let input_slot: Arc<Mutex<Option<InputInjector>>> = Arc::new(Mutex::new(None));
    host.spawn_capture_loop(target_fps, idle_fps, Arc::clone(&input_slot));

    while let Some(evt) = signaling.recv().await {
        match evt {
            SignalingEvent::PeerJoined => {
                info!("viewer joined — sending offer");
                host.create_and_send_offer().await?;
            }
            SignalingEvent::Answer(sdp) => {
                host.handle_answer(sdp).await?;
            }
            SignalingEvent::IceCandidate {
                candidate,
                sdp_mid,
                sdp_mline_index,
            } => {
                host.add_ice_candidate(candidate, sdp_mid, sdp_mline_index)
                    .await?;
            }
            SignalingEvent::PeerLeft => {
                info!("viewer disconnected");
                host.stream_video.store(false, Ordering::SeqCst);
            }
            SignalingEvent::Error(m) => {
                warn!("signaling error: {m}");
            }
            SignalingEvent::Offer(_) => {}
        }
    }
    Ok(())
}
