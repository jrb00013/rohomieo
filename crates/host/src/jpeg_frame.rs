//! Phone-friendly JPEG frames over the WebRTC datachannel.
//!
//! Quality strategy (aligned with TurboVNC / KasmVNC “high” presets):
//! - Prefer native resolution up to 1920px wide (enough to zoom without mush).
//! - JPEG quality ≥90 → 4:4:4 chroma (no 4:2:0 smear on colored UI text).
//! - When we must downscale, use Lanczos3 (better edge/text retention than
//!   Triangle/bilinear). Soften size with quality first; scale only as last resort.

use anyhow::{anyhow, Result};
use image::imageops::FilterType;
use image::{ImageBuffer, Rgb};
use jpeg_encoder::{ColorType, Encoder, SamplingFactor};

/// Match KasmVNC “High/Extreme” video max width — sharp enough for phone zoom.
const MAX_STREAM_WIDTH: u32 = 1920;
/// Stay under the SCTP send cap (256–512 KiB) with headroom.
const MAX_JPEG_BYTES: usize = 220_000;
/// TurboVNC “perceptually lossless” neighborhood; enables 4:4:4 in jpeg-encoder.
const HIGH_QUALITY: u8 = 90;

/// Downscale if needed and encode BGRA (scrap) to JPEG for datachannel fallback.
pub fn bgra_to_jpeg(bgra: &[u8], width: usize, height: usize, stride: usize) -> Result<Vec<u8>> {
    let img = bgra_to_rgb(bgra, width, height, stride)?;
    let img = fit_width(img, MAX_STREAM_WIDTH);
    encode_with_budget(&img)
}

fn bgra_to_rgb(
    bgra: &[u8],
    width: usize,
    height: usize,
    stride: usize,
) -> Result<ImageBuffer<Rgb<u8>, Vec<u8>>> {
    let mut rgb = vec![0u8; width.saturating_mul(height).saturating_mul(3)];
    for y in 0..height {
        let row = y * stride;
        let dst_row = y * width * 3;
        for x in 0..width {
            let i = row + x * 4;
            if i + 2 >= bgra.len() {
                continue;
            }
            let o = dst_row + x * 3;
            // scrap DXGI is BGRA → JPEG needs RGB
            rgb[o] = bgra[i + 2];
            rgb[o + 1] = bgra[i + 1];
            rgb[o + 2] = bgra[i];
        }
    }
    ImageBuffer::from_raw(width as u32, height as u32, rgb)
        .ok_or_else(|| anyhow!("RGB buffer size mismatch"))
}

fn fit_width(
    img: ImageBuffer<Rgb<u8>, Vec<u8>>,
    max_w: u32,
) -> ImageBuffer<Rgb<u8>, Vec<u8>> {
    if img.width() <= max_w {
        return img;
    }
    let nh = ((img.height() as u64 * max_w as u64) / img.width() as u64).max(1) as u32;
    image::imageops::resize(&img, max_w, nh, FilterType::Lanczos3)
}

fn encode_rgb(
    img: &ImageBuffer<Rgb<u8>, Vec<u8>>,
    quality: u8,
    sampling: SamplingFactor,
) -> Result<Vec<u8>> {
    let mut out = Vec::with_capacity(96 * 1024);
    let mut enc = Encoder::new(&mut out, quality);
    enc.set_sampling_factor(sampling);
    enc.encode(
        img.as_raw(),
        img.width()
            .try_into()
            .map_err(|_| anyhow!("frame width exceeds JPEG limit"))?,
        img.height()
            .try_into()
            .map_err(|_| anyhow!("frame height exceeds JPEG limit"))?,
        ColorType::Rgb,
    )
    .map_err(|e| anyhow!("jpeg encode: {e}"))?;
    Ok(out)
}

fn encode_with_budget(img: &ImageBuffer<Rgb<u8>, Vec<u8>>) -> Result<Vec<u8>> {
    // High quality + 4:4:4 first (sharp text / UI).
    let mut out = encode_rgb(img, HIGH_QUALITY, SamplingFactor::R_4_4_4)?;
    if out.len() <= MAX_JPEG_BYTES {
        return Ok(out);
    }

    // Soften quant tables before throwing away pixels.
    for q in [85_u8, 78, 70] {
        out = encode_rgb(img, q, SamplingFactor::R_4_4_4)?;
        if out.len() <= MAX_JPEG_BYTES {
            return Ok(out);
        }
    }

    // Still huge → allow 4:2:0 chroma (common JPEG) at mid-high quality.
    out = encode_rgb(img, 78, SamplingFactor::R_4_2_0)?;
    if out.len() <= MAX_JPEG_BYTES {
        return Ok(out);
    }

    // Last resort: Lanczos downscale, then re-encode high.
    for &max_w in &[1600_u32, 1280, 1024] {
        if img.width() <= max_w {
            continue;
        }
        let smaller = fit_width(img.clone(), max_w);
        out = encode_rgb(&smaller, HIGH_QUALITY, SamplingFactor::R_4_4_4)?;
        if out.len() <= MAX_JPEG_BYTES {
            return Ok(out);
        }
        out = encode_rgb(&smaller, 80, SamplingFactor::R_4_2_0)?;
        if out.len() <= MAX_JPEG_BYTES {
            return Ok(out);
        }
    }

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bgra_jpeg_encodes_nonempty() {
        let w = 64usize;
        let h = 48usize;
        let mut bgra = vec![0u8; w * h * 4];
        for px in bgra.chunks_exact_mut(4) {
            px[0] = 40;
            px[1] = 80;
            px[2] = 160;
            px[3] = 255;
        }
        let jpeg = bgra_to_jpeg(&bgra, w, h, w * 4).expect("jpeg");
        assert!(jpeg.len() > 100, "got {} bytes", jpeg.len());
        assert_eq!(&jpeg[..2], &[0xff, 0xd8]);
    }

    #[test]
    fn large_frame_stays_under_budget() {
        let w = 1920usize;
        let h = 1080usize;
        let mut bgra = vec![0u8; w * h * 4];
        for (i, px) in bgra.chunks_exact_mut(4).enumerate() {
            let x = (i % w) as u8;
            let y = (i / w) as u8;
            px[0] = x;
            px[1] = y;
            px[2] = x.wrapping_add(y);
            px[3] = 255;
        }
        let jpeg = bgra_to_jpeg(&bgra, w, h, w * 4).expect("jpeg");
        assert!(
            jpeg.len() <= MAX_JPEG_BYTES + 32_000,
            "jpeg {} exceeds soft budget",
            jpeg.len()
        );
        assert_eq!(&jpeg[..2], &[0xff, 0xd8]);
    }
}
