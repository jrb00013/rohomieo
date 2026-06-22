//! Adaptive FPS: throttle when the desktop is static.

const TILE: usize = 32;

pub struct MotionDetector {
    prev: Vec<u8>,
    width: usize,
    height: usize,
    stride: usize,
    idle_streak: u32,
}

impl MotionDetector {
    pub fn new(width: usize, height: usize, stride: usize) -> Self {
        Self {
            prev: vec![0; width * height],
            width,
            height,
            stride,
            idle_streak: 0,
        }
    }

    /// Returns true if the frame should be encoded (motion or heartbeat).
    pub fn should_encode(&mut self, bgra: &[u8], force_heartbeat: bool) -> bool {
        if force_heartbeat {
            self.idle_streak = 0;
            self.store_downsampled(bgra);
            return true;
        }

        let changed = self.changed_ratio(bgra);
        const IDLE_THRESHOLD: f64 = 0.02;
        if changed < IDLE_THRESHOLD {
            self.idle_streak += 1;
            // Send at least one frame every ~2s when idle (every 10 skipped 5fps ticks)
            if self.idle_streak % 10 == 0 {
                self.store_downsampled(bgra);
                return true;
            }
            false
        } else {
            self.idle_streak = 0;
            self.store_downsampled(bgra);
            true
        }
    }

    pub fn is_idle(&self) -> bool {
        self.idle_streak > 2
    }

    fn changed_ratio(&self, bgra: &[u8]) -> f64 {
        let tw = (self.width / TILE).max(1);
        let th = (self.height / TILE).max(1);
        let mut changed_tiles = 0u32;
        let total = (tw * th) as u32;

        for ty in 0..th {
            for tx in 0..tw {
                let x0 = tx * TILE;
                let y0 = ty * TILE;
                let mut diff = 0u32;
                let samples = 4usize;
                for sy in 0..samples {
                    for sx in 0..samples {
                        let x = (x0 + sx * TILE / samples).min(self.width.saturating_sub(1));
                        let y = (y0 + sy * TILE / samples).min(self.height.saturating_sub(1));
                        let i = y * self.stride + x * 4;
                        if i + 2 >= bgra.len() {
                            continue;
                        }
                        let pi = y * self.width + x;
                        let old = self.prev[pi];
                        let new = bgra[i];
                        if (old as i16 - new as i16).unsigned_abs() > 12 {
                            diff += 1;
                        }
                    }
                }
                if diff > samples as u32 {
                    changed_tiles += 1;
                }
            }
        }
        changed_tiles as f64 / total as f64
    }

    fn store_downsampled(&mut self, bgra: &[u8]) {
        for y in 0..self.height {
            for x in 0..self.width {
                let i = y * self.stride + x * 4;
                let pi = y * self.width + x;
                if i < bgra.len() {
                    self.prev[pi] = bgra[i];
                }
            }
        }
    }
}

pub fn target_frame_interval(idle: bool, target_fps: u32, idle_fps: u32) -> std::time::Duration {
    let fps = if idle { idle_fps } else { target_fps };
    std::time::Duration::from_secs_f64(1.0 / fps.max(1) as f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_interval_uses_idle_fps() {
        let d = target_frame_interval(true, 30, 8);
        assert!((d.as_secs_f64() - 0.125).abs() < 0.001);
    }

    #[test]
    fn static_frame_skips_encode() {
        let mut det = MotionDetector::new(64, 64, 64 * 4);
        let frame = vec![128u8; 64 * 64 * 4];
        det.should_encode(&frame, true);
        assert!(!det.should_encode(&frame, false));
    }
}
