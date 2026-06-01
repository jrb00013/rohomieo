use anyhow::Result;
use openh264::encoder::{Encoder, EncoderConfig, RateControlMode, UsageType};
use openh264::OpenH264API;
use openh264::formats::YUVSource;
use openh264::Error;

/// BGRA (scrap) → I420 for OpenH264.
pub fn bgra_to_i420(bgra: &[u8], width: usize, height: usize, stride: usize) -> Vec<u8> {
    let chroma_w = (width + 1) / 2;
    let chroma_h = (height + 1) / 2;
    let mut i420 = vec![0u8; width * height + 2 * chroma_w * chroma_h];
    let (y_plane, uv) = i420.split_at_mut(width * height);
    let (u_plane, v_plane) = uv.split_at_mut(chroma_w * chroma_h);

    for y in 0..height {
        for x in 0..width {
            let i = y * stride + x * 4;
            if i + 3 >= bgra.len() {
                continue;
            }
            let b = bgra[i] as i32;
            let g = bgra[i + 1] as i32;
            let r = bgra[i + 2] as i32;
            let y_val = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            y_plane[y * width + x] = y_val.clamp(0, 255) as u8;
            if x % 2 == 0 && y % 2 == 0 {
                let u_val = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                let v_val = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                let uv_x = x / 2;
                let uv_y = y / 2;
                let uv_idx = uv_y * chroma_w + uv_x;
                if uv_idx < u_plane.len() {
                    u_plane[uv_idx] = u_val.clamp(0, 255) as u8;
                    v_plane[uv_idx] = v_val.clamp(0, 255) as u8;
                }
            }
        }
    }
    i420
}

struct I420Buffer<'a> {
    data: &'a [u8],
    width: usize,
    height: usize,
}

impl YUVSource for I420Buffer<'_> {
    fn dimensions(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    fn strides(&self) -> (usize, usize, usize) {
        let chroma_w = (self.width + 1) / 2;
        (self.width, chroma_w, chroma_w)
    }

    fn y(&self) -> &[u8] {
        &self.data[..self.width * self.height]
    }

    fn u(&self) -> &[u8] {
        let base = self.width * self.height;
        let chroma_w = (self.width + 1) / 2;
        let chroma_h = (self.height + 1) / 2;
        &self.data[base..base + chroma_w * chroma_h]
    }

    fn v(&self) -> &[u8] {
        let base = self.width * self.height;
        let chroma_w = (self.width + 1) / 2;
        let chroma_h = (self.height + 1) / 2;
        let u_len = chroma_w * chroma_h;
        &self.data[base + u_len..base + 2 * u_len]
    }
}

pub struct H264Encoder {
    encoder: Encoder,
    width: u32,
    height: u32,
    i420_buf: Vec<u8>,
    frames_encoded: u64,
}

impl H264Encoder {
    pub fn new(width: u32, height: u32) -> Result<Self> {
        let config = EncoderConfig::new()
            .set_bitrate_bps(2_500_000)
            .max_frame_rate(30.0)
            .usage_type(UsageType::ScreenContentRealTime)
            .rate_control_mode(RateControlMode::Bitrate);
        let encoder =
            Encoder::with_api_config(OpenH264API::from_source(), config)
                .map_err(|e: Error| anyhow::anyhow!("{e}"))?;
        let chroma_w = ((width as usize) + 1) / 2;
        let chroma_h = ((height as usize) + 1) / 2;
        let i420_len = width as usize * height as usize + 2 * chroma_w * chroma_h;
        Ok(Self {
            encoder,
            width,
            height,
            i420_buf: vec![0; i420_len],
            frames_encoded: 0,
        })
    }

    pub fn encode_bgra(
        &mut self,
        bgra: &[u8],
        width: usize,
        height: usize,
        stride: usize,
    ) -> Result<Option<Vec<u8>>> {
        let min_len = height.saturating_mul(stride);
        if bgra.len() < min_len {
            anyhow::bail!(
                "frame buffer too small: {} bytes, need at least {} ({}x{} stride {})",
                bgra.len(),
                min_len,
                width,
                height,
                stride
            );
        }

        if width as u32 != self.width || height as u32 != self.height {
            self.width = width as u32;
            self.height = height as u32;
            let chroma_w = (width + 1) / 2;
            let chroma_h = (height + 1) / 2;
            self.i420_buf.resize(width * height + 2 * chroma_w * chroma_h, 0);
            self.encoder.force_intra_frame();
        }

        if self.frames_encoded == 0 {
            self.encoder.force_intra_frame();
        }

        self.i420_buf = bgra_to_i420(bgra, width, height, stride);
        let src = I420Buffer {
            data: &self.i420_buf,
            width,
            height,
        };
        let bitstream = self
            .encoder
            .encode(&src)
            .map_err(|e: Error| anyhow::anyhow!("{e}"))?;
        let vec = bitstream.to_vec();
        self.frames_encoded += 1;
        if vec.is_empty() {
            Ok(None)
        } else {
            Ok(Some(vec))
        }
    }
}
