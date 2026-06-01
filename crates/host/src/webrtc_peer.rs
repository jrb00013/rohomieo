use crate::capture::ScreenCapture;
use crate::encode::H264Encoder;
use crate::input::InputInjector;
use crate::motion::MotionDetector;
use crate::signaling_client::{SignalingClient, SignalingEvent};
use anyhow::Result;
use bytes::Bytes;
use interceptor::registry::Registry;
use rohomieo_proto::{InputEvent, SignalMessage};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{info, warn};
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::api::media_engine::{MediaEngine, MIME_TYPE_H264};
use webrtc::api::APIBuilder;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
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

        let dc = pc
            .create_data_channel(
                "input",
                Some(webrtc::data_channel::data_channel_init::RTCDataChannelInit {
                    ordered: Some(true),
                    ..Default::default()
                }),
            )
            .await?;

        let input_dc = Arc::clone(&input_slot);
        dc.on_message(Box::new(move |msg: DataChannelMessage| {
            let input_dc = Arc::clone(&input_dc);
            Box::pin(async move {
                if let Ok(evt) = InputEvent::from_json(&String::from_utf8_lossy(&msg.data)) {
                    if let Some(inj) = input_dc.lock().await.as_mut() {
                        inj.handle(evt);
                    }
                }
            })
        }));

        Ok(Self {
            pc,
            video_track,
            signaling,
        })
    }

    pub async fn create_and_send_offer(&self) -> Result<()> {
        let offer = self.pc.create_offer(None).await?;
        self.pc.set_local_description(offer.clone()).await?;
        self.signaling.send(SignalMessage::Offer {
            sdp: offer.sdp,
        });
        Ok(())
    }

    pub async fn handle_answer(&self, sdp: String) -> Result<()> {
        let answer = RTCSessionDescription::answer(sdp)?;
        self.pc.set_remote_description(answer).await?;
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
        tokio::spawn(async move {
            if let Err(e) = run_capture_loop(video_track, target_fps, idle_fps, input_slot).await
            {
                warn!("capture loop ended: {e}");
            }
        });
    }
}

async fn run_capture_loop(
    video_track: Arc<TrackLocalStaticSample>,
    target_fps: u32,
    idle_fps: u32,
    input_slot: Arc<Mutex<Option<InputInjector>>>,
) -> Result<()> {
    let mut cap = ScreenCapture::primary()?;
    let (w, h) = cap.dimensions();
    let stride = cap.stride();

    {
        let mut guard = input_slot.lock().await;
        *guard = Some(InputInjector::new(w as i32, h as i32)?);
    }

    let mut motion = MotionDetector::new(w, h, stride);
    let mut encoder = H264Encoder::new(w as u32, h as u32)?;
    let frame_duration = Duration::from_millis(1000 / target_fps.max(1) as u64);
    let mut heartbeat_ticks = 0u32;

    loop {
        let idle = motion.is_idle();
        let delay = cap.frame_delay(idle, target_fps, idle_fps);
        tokio::time::sleep(delay).await;

        let Some(bgra) = cap.capture_frame().await? else {
            continue;
        };

        heartbeat_ticks += 1;
        let force_hb = heartbeat_ticks % 50 == 0;
        if !motion.should_encode(&bgra, force_hb) {
            continue;
        }

        if let Some(h264) = encoder.encode_bgra(&bgra, w, h, stride)? {
            let _ = video_track
                .write_sample(&Sample {
                    data: Bytes::from(h264),
                    duration: frame_duration,
                    ..Default::default()
                })
                .await;
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
            }
            SignalingEvent::Error(m) => {
                warn!("signaling error: {m}");
            }
            SignalingEvent::Offer(_) => {}
        }
    }
    Ok(())
}
