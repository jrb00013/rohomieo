use anyhow::{Context, Result};
use scrap::{Capturer, Display};
use std::time::Duration;
use tokio::sync::mpsc;

pub struct ScreenCapture {
    rx: mpsc::Receiver<Vec<u8>>,
    width: usize,
    height: usize,
    stride: usize,
}

impl ScreenCapture {
    pub fn primary() -> Result<Self> {
        let display = Display::primary().context("no primary display")?;
        let capturer = Capturer::new(display).context("create capturer")?;
        let width = capturer.width();
        let height = capturer.height();
        let stride = width * 4;

        let (tx, rx) = mpsc::channel(4);

        std::thread::spawn(move || {
            let display = match Display::primary() {
                Ok(d) => d,
                Err(_) => return,
            };
            let mut capturer = match Capturer::new(display) {
                Ok(c) => c,
                Err(_) => return,
            };
            loop {
                match capturer.frame() {
                    Ok(frame) => {
                        if tx.blocking_send(frame.to_vec()).is_err() {
                            break;
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        std::thread::sleep(Duration::from_millis(2));
                    }
                    Err(_) => std::thread::sleep(Duration::from_millis(16)),
                }
            }
        });

        Ok(Self {
            rx,
            width,
            height,
            stride,
        })
    }

    pub fn dimensions(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    pub fn stride(&self) -> usize {
        self.stride
    }

    /// Latest frame from the capture thread, if any.
    pub async fn capture_frame(&mut self) -> Result<Option<Vec<u8>>> {
        // Drain to latest frame
        let mut latest = None;
        while let Ok(frame) = self.rx.try_recv() {
            latest = Some(frame);
        }
        if latest.is_some() {
            return Ok(latest);
        }
        match tokio::time::timeout(Duration::from_millis(100), self.rx.recv()).await {
            Ok(Some(f)) => Ok(Some(f)),
            _ => Ok(None),
        }
    }

    pub fn frame_delay(&self, idle: bool, target_fps: u32, idle_fps: u32) -> Duration {
        crate::motion::target_frame_interval(idle, target_fps, idle_fps)
    }
}

#[cfg(target_os = "macos")]
pub fn macos_permission_hint() {
    eprintln!(
        "macOS: grant Screen Recording to this app in System Settings → Privacy & Security"
    );
}

#[cfg(not(target_os = "macos"))]
pub fn macos_permission_hint() {}
