//! Decoding into 8-bit RGB with hard limits. Transparency is flattened onto black, which is what the Go renderer's
//! JPEG encoder does with alpha, so thumbnails match.

use crate::exif;
use std::io::Cursor;

/// Largest decoded image, in pixels (the Go renderer's budget).
pub const MAX_PIXELS: u64 = 40_000_000;

#[derive(Debug)]
pub enum DecodeError {
    /// Not an image this process can decode (the agent falls back to its own decoder).
    Unsupported(String),
    /// Over the pixel budget.
    TooLarge(String),
}

impl DecodeError {
    fn unsupported(e: impl std::fmt::Display) -> Self {
        DecodeError::Unsupported(e.to_string())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Jpeg,
    Png,
    Gif,
    Webp,
}

impl Format {
    pub fn name(self) -> &'static str {
        match self {
            Format::Jpeg => "jpeg",
            Format::Png => "png",
            Format::Gif => "gif",
            Format::Webp => "webp",
        }
    }
}

pub fn sniff(data: &[u8]) -> Option<Format> {
    if data.starts_with(&[0xff, 0xd8, 0xff]) {
        Some(Format::Jpeg)
    } else if data.starts_with(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]) {
        Some(Format::Png)
    } else if data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a") {
        Some(Format::Gif)
    } else if data.len() >= 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        Some(Format::Webp)
    } else {
        None
    }
}

#[derive(Debug)]
pub struct Decoded {
    pub format: Format,
    /// Dimensions of the source image as stored.
    pub src_width: u32,
    pub src_height: u32,
    /// Dimensions of `rgb` (smaller than the source when the decoder scaled the JPEG down).
    pub width: u32,
    pub height: u32,
    pub rgb: Vec<u8>,
    /// EXIF orientation, 1-8.
    pub orientation: u8,
}

fn check_pixels(w: u64, h: u64) -> Result<(), DecodeError> {
    if w == 0 || h == 0 {
        return Err(DecodeError::Unsupported(format!(
            "invalid image dimensions {w}x{h}"
        )));
    }
    if w * h > MAX_PIXELS {
        return Err(DecodeError::TooLarge(format!(
            "{w}x{h} exceeds the pixel budget"
        )));
    }
    Ok(())
}

/// Decodes `data`. `want` is the longest side the caller will end up with after fitting; a JPEG may be decoded at a
/// reduced size (never below twice that, so the resize still has real data to work with).
pub fn decode(data: &[u8], want: u32) -> Result<Decoded, DecodeError> {
    match sniff(data) {
        Some(Format::Jpeg) => jpeg(data, want),
        Some(Format::Png) => png(data),
        Some(Format::Gif) => gif(data),
        Some(Format::Webp) => webp(data),
        None => Err(DecodeError::Unsupported("not a supported image".into())),
    }
}

fn jpeg(data: &[u8], want: u32) -> Result<Decoded, DecodeError> {
    let mut dec = jpeg_decoder::Decoder::new(Cursor::new(data));
    dec.read_info().map_err(DecodeError::unsupported)?;
    let info = dec
        .info()
        .ok_or_else(|| DecodeError::Unsupported("no image info".into()))?;
    let (sw, sh) = (info.width as u32, info.height as u32);
    check_pixels(sw as u64, sh as u64)?;
    let orientation = dec.exif_data().map(exif::orientation).unwrap_or(1);

    // Ask for twice the final size: the DCT scale only ever halves, and Lanczos does the rest.
    let long = sw.max(sh);
    if want > 0 && long > want {
        let f = (want as f64 * 2.0 / long as f64).min(1.0);
        let rw = ((sw as f64 * f).ceil() as u32).clamp(1, u16::MAX as u32) as u16;
        let rh = ((sh as f64 * f).ceil() as u32).clamp(1, u16::MAX as u32) as u16;
        dec.scale(rw, rh).map_err(DecodeError::unsupported)?;
    }
    let pixels = dec.decode().map_err(DecodeError::unsupported)?;
    let info = dec
        .info()
        .ok_or_else(|| DecodeError::Unsupported("no image info".into()))?;
    let (w, h) = (info.width as u32, info.height as u32);
    let n = (w as usize) * (h as usize);
    let rgb = match info.pixel_format {
        jpeg_decoder::PixelFormat::RGB24 => pixels,
        jpeg_decoder::PixelFormat::L8 => pixels.iter().flat_map(|&g| [g, g, g]).collect(),
        jpeg_decoder::PixelFormat::L16 => pixels
            .as_chunks::<2>()
            .0
            .iter()
            .flat_map(|c| [c[0], c[0], c[0]])
            .collect(),
        jpeg_decoder::PixelFormat::CMYK32 => {
            let mut out = Vec::with_capacity(n * 3);
            for c in pixels.as_chunks::<4>().0 {
                // The decoder returns ink amounts (0 = no ink), the same values Go's image.CMYK holds.
                let k = 255 - c[3] as u32;
                out.extend_from_slice(&[
                    ((255 - c[0] as u32) * k / 255) as u8,
                    ((255 - c[1] as u32) * k / 255) as u8,
                    ((255 - c[2] as u32) * k / 255) as u8,
                ]);
            }
            out
        }
    };
    if rgb.len() != n * 3 {
        return Err(DecodeError::Unsupported("unexpected decoded size".into()));
    }
    Ok(Decoded {
        format: Format::Jpeg,
        src_width: sw,
        src_height: sh,
        width: w,
        height: h,
        rgb,
        orientation,
    })
}

/// Flattens RGBA onto black (premultiplying), like the Go JPEG encoder does.
fn flatten_rgba(rgba: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(rgba.len() / 4 * 3);
    for p in rgba.as_chunks::<4>().0 {
        let a = p[3] as u32;
        out.extend_from_slice(&[
            ((p[0] as u32 * a + 127) / 255) as u8,
            ((p[1] as u32 * a + 127) / 255) as u8,
            ((p[2] as u32 * a + 127) / 255) as u8,
        ]);
    }
    out
}

fn png(data: &[u8]) -> Result<Decoded, DecodeError> {
    let mut dec = png::Decoder::new(Cursor::new(data));
    dec.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = dec.read_info().map_err(DecodeError::unsupported)?;
    let (w, h) = {
        let i = reader.info();
        (i.width, i.height)
    };
    check_pixels(w as u64, h as u64)?;
    let mut buf = vec![0u8; reader.output_buffer_size()];
    let frame = reader
        .next_frame(&mut buf)
        .map_err(DecodeError::unsupported)?;
    let buf = &buf[..frame.buffer_size()];
    let rgb = match frame.color_type {
        png::ColorType::Rgb => buf.to_vec(),
        png::ColorType::Rgba => flatten_rgba(buf),
        png::ColorType::Grayscale => buf.iter().flat_map(|&g| [g, g, g]).collect(),
        png::ColorType::GrayscaleAlpha => buf
            .as_chunks::<2>()
            .0
            .iter()
            .flat_map(|c| {
                let v = ((c[0] as u32 * c[1] as u32 + 127) / 255) as u8;
                [v, v, v]
            })
            .collect(),
        png::ColorType::Indexed => {
            return Err(DecodeError::Unsupported("unexpanded palette".into()))
        }
    };
    Ok(Decoded {
        format: Format::Png,
        src_width: w,
        src_height: h,
        width: w,
        height: h,
        rgb,
        orientation: 1,
    })
}

fn gif(data: &[u8]) -> Result<Decoded, DecodeError> {
    let mut opts = gif::DecodeOptions::new();
    opts.set_color_output(gif::ColorOutput::RGBA);
    let mut dec = opts
        .read_info(Cursor::new(data))
        .map_err(DecodeError::unsupported)?;
    check_pixels(dec.width() as u64, dec.height() as u64)?;
    let frame = dec
        .read_next_frame()
        .map_err(DecodeError::unsupported)?
        .ok_or_else(|| DecodeError::Unsupported("gif without frames".into()))?;
    // Like Go's decoder, the thumbnail is the first frame's own rectangle.
    let (w, h) = (frame.width as u32, frame.height as u32);
    check_pixels(w as u64, h as u64)?;
    Ok(Decoded {
        format: Format::Gif,
        src_width: w,
        src_height: h,
        width: w,
        height: h,
        rgb: flatten_rgba(&frame.buffer),
        orientation: 1,
    })
}

fn webp(data: &[u8]) -> Result<Decoded, DecodeError> {
    let mut dec =
        image_webp::WebPDecoder::new(Cursor::new(data)).map_err(DecodeError::unsupported)?;
    let (w, h) = dec.dimensions();
    check_pixels(w as u64, h as u64)?;
    let size = dec
        .output_buffer_size()
        .ok_or_else(|| DecodeError::TooLarge("webp output size overflows".into()))?;
    let mut buf = vec![0u8; size];
    dec.read_image(&mut buf).map_err(DecodeError::unsupported)?;
    let rgb = if dec.has_alpha() {
        flatten_rgba(&buf)
    } else {
        buf
    };
    Ok(Decoded {
        format: Format::Webp,
        src_width: w,
        src_height: h,
        width: w,
        height: h,
        rgb,
        orientation: 1,
    })
}
