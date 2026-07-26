use anyhow::Result;
use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::{ImageBuffer, Rgb};

const MAX_STREAM_WIDTH: u32 = 960;

/// Downscale if needed and encode BGRA (scrap) to JPEG for datachannel fallback.
pub fn bgra_to_jpeg(bgra: &[u8], width: usize, height: usize, stride: usize) -> Result<Vec<u8>> {
    let mut img: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::new(width as u32, height as u32);
    for y in 0..height {
        for x in 0..width {
            let i = y * stride + x * 4;
            if i + 3 >= bgra.len() {
                continue;
            }
            // scrap DXGI is BGRA → JPEG needs RGB
            img.put_pixel(
                x as u32,
                y as u32,
                Rgb([bgra[i + 2], bgra[i + 1], bgra[i]]),
            );
        }
    }

    let img = if width as u32 > MAX_STREAM_WIDTH {
        let nh = (height as u32 * MAX_STREAM_WIDTH) / width as u32;
        image::imageops::resize(&img, MAX_STREAM_WIDTH, nh.max(1), FilterType::Triangle)
    } else {
        img
    };

    // JpegEncoder only accepts RGB8/L8 (not Rgba8).
    encode_rgb_jpeg(&img, 55)
}

fn encode_rgb_jpeg(img: &ImageBuffer<Rgb<u8>, Vec<u8>>, quality: u8) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    let mut enc = JpegEncoder::new_with_quality(&mut out, quality);
    enc.encode(
        img.as_raw(),
        img.width(),
        img.height(),
        image::ExtendedColorType::Rgb8,
    )?;
    if out.len() > 60_000 {
        let nw = (img.width() * 3 / 4).max(320);
        let nh = (img.height() * 3 / 4).max(180);
        let small = image::imageops::resize(img, nw, nh, FilterType::Triangle);
        out.clear();
        let mut enc = JpegEncoder::new_with_quality(&mut out, 45);
        enc.encode(
            small.as_raw(),
            small.width(),
            small.height(),
            image::ExtendedColorType::Rgb8,
        )?;
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
}
