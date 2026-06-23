use anyhow::Result;
use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::{ImageBuffer, Rgba};

const MAX_STREAM_WIDTH: u32 = 1280;

/// Downscale if needed and encode BGRA (scrap) to JPEG for datachannel fallback.
pub fn bgra_to_jpeg(bgra: &[u8], width: usize, height: usize, stride: usize) -> Result<Vec<u8>> {
    let mut img: ImageBuffer<Rgba<u8>, Vec<u8>> = ImageBuffer::new(width as u32, height as u32);
    for y in 0..height {
        for x in 0..width {
            let i = y * stride + x * 4;
            if i + 3 >= bgra.len() {
                continue;
            }
            img.put_pixel(
                x as u32,
                y as u32,
                Rgba([bgra[i + 2], bgra[i + 1], bgra[i], 255]),
            );
        }
    }

    let img = if width as u32 > MAX_STREAM_WIDTH {
        let nh = (height as u32 * MAX_STREAM_WIDTH) / width as u32;
        image::imageops::resize(&img, MAX_STREAM_WIDTH, nh.max(1), FilterType::Triangle)
    } else {
        img
    };

    let mut out = Vec::new();
    let mut enc = JpegEncoder::new_with_quality(&mut out, 72);
    enc.encode(
        img.as_raw(),
        img.width(),
        img.height(),
        image::ExtendedColorType::Rgba8,
    )?;
    Ok(out)
}
