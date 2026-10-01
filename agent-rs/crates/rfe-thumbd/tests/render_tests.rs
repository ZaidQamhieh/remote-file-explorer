use rfe_thumbd::decode::{self, DecodeError};
use rfe_thumbd::render::{self, RenderError};

fn data(name: &str) -> Vec<u8> {
    std::fs::read(format!("{}/tests/data/{name}", env!("CARGO_MANIFEST_DIR"))).unwrap()
}

/// Decodes a thumbnail back to RGB for inspection.
fn pixels(jpeg: &[u8]) -> (usize, usize, Vec<u8>) {
    let mut d = jpeg_decoder::Decoder::new(jpeg);
    let px = d.decode().unwrap();
    let i = d.info().unwrap();
    assert_eq!(i.pixel_format, jpeg_decoder::PixelFormat::RGB24);
    (i.width as usize, i.height as usize, px)
}

fn at(img: &(usize, usize, Vec<u8>), x: usize, y: usize) -> [u8; 3] {
    let o = (y * img.0 + x) * 3;
    [img.2[o], img.2[o + 1], img.2[o + 2]]
}

fn is_red(p: [u8; 3]) -> bool {
    p[0] > 190 && p[1] < 90 && p[2] < 90
}

fn near(a: [u8; 3], b: [u8; 3], tol: i32) -> bool {
    a.iter()
        .zip(b)
        .all(|(x, y)| (*x as i32 - y as i32).abs() <= tol)
}

#[test]
fn a_landscape_photo_is_fitted_and_never_upscaled() {
    let t = render::render(&data("photo.jpg"), 128).unwrap();
    assert_eq!(
        (t.width, t.height, t.src_width, t.src_height),
        (128, 96, 400, 300)
    );
    assert_eq!(t.format, "jpeg");
    let t = render::render(&data("photo.jpg"), 1024).unwrap();
    assert_eq!(
        (t.width, t.height),
        (400, 300),
        "smaller than the box stays as it is"
    );
    let img = pixels(&render::render(&data("photo.jpg"), 128).unwrap().jpeg);
    assert!(is_red(at(&img, 40, 30)), "the red block is top left");
}

#[test]
fn exif_orientation_is_applied_before_fitting() {
    let t = render::render(&data("orient6.jpg"), 128).unwrap();
    assert_eq!((t.width, t.height), (96, 128), "rotated to portrait");
    let img = pixels(&t.jpeg);
    // Rotated 90 degrees clockwise, the block that was top left is top right.
    assert!(is_red(at(&img, 70, 20)), "{:?}", at(&img, 70, 20));
    assert!(!is_red(at(&img, 20, 20)));

    let t = render::render(&data("orient3.jpg"), 128).unwrap();
    assert_eq!((t.width, t.height), (128, 96));
    let img = pixels(&t.jpeg);
    assert!(
        is_red(at(&img, 128 - 40, 96 - 30)),
        "rotated 180: bottom right"
    );
}

#[test]
fn every_decoder_produces_a_thumbnail() {
    for (name, w, h) in [
        ("gray.jpg", 128, 96),
        ("cmyk.jpg", 128, 96),
        ("progressive.jpg", 128, 96),
        ("palette.png", 128, 96),
        ("gray16.png", 64, 64),
        ("alpha.png", 128, 64),
        ("anim.gif", 120, 80),
        ("lossy.webp", 128, 96),
        ("alpha.webp", 128, 64),
    ] {
        let t = render::render(&data(name), 128).unwrap_or_else(|e| panic!("{name}: {e:?}"));
        assert_eq!((t.width, t.height), (w, h), "{name}");
        let _ = pixels(&t.jpeg);
    }
}

#[test]
fn colours_survive() {
    let cmyk = pixels(&render::render(&data("cmyk.jpg"), 128).unwrap().jpeg);
    assert!(
        is_red(at(&cmyk, 40, 30)),
        "cmyk red block: {:?}",
        at(&cmyk, 40, 30)
    );
    let gray = pixels(&render::render(&data("gray16.png"), 64).unwrap().jpeg);
    assert!(
        near(at(&gray, 10, 10), [156, 156, 156], 4),
        "{:?}",
        at(&gray, 10, 10)
    );
    // Transparency is flattened onto black: transparent on the left, opaque orange on the right.
    let alpha = pixels(&render::render(&data("alpha.png"), 200).unwrap().jpeg);
    assert!(
        near(at(&alpha, 2, 50), [0, 0, 0], 12),
        "{:?}",
        at(&alpha, 2, 50)
    );
    assert!(
        near(at(&alpha, 197, 50), [255, 128, 0], 24),
        "{:?}",
        at(&alpha, 197, 50)
    );
}

#[test]
fn big_jpegs_are_decoded_at_a_reduced_size() {
    let (w, h) = (4000usize, 3000usize);
    let mut rgb = vec![0u8; w * h * 3];
    for y in 0..h {
        for x in 0..w {
            let o = (y * w + x) * 3;
            rgb[o] = (x * 255 / w) as u8;
            rgb[o + 1] = (y * 255 / h) as u8;
            rgb[o + 2] = 90;
        }
    }
    let mut jpeg = Vec::new();
    jpeg_encoder::Encoder::new(&mut jpeg, 85)
        .encode(&rgb, w as u16, h as u16, jpeg_encoder::ColorType::Rgb)
        .unwrap();
    let d = decode::decode(&jpeg, 256).unwrap();
    assert_eq!((d.src_width, d.src_height), (4000, 3000));
    assert!(
        d.width < d.src_width && d.width >= 512,
        "DCT scaled: {}x{}",
        d.width,
        d.height
    );
    let t = render::render(&jpeg, 256).unwrap();
    assert_eq!((t.width, t.height), (256, 192));
    let img = pixels(&t.jpeg);
    assert!(
        near(at(&img, 128, 96), [127, 127, 90], 8),
        "{:?}",
        at(&img, 128, 96)
    );
}

#[test]
fn bad_input_is_refused_not_crashed_on() {
    assert!(matches!(
        render::render(&data("notimage.bin"), 128),
        Err(RenderError::Decode(DecodeError::Unsupported(_)))
    ));
    assert!(matches!(
        render::render(b"", 128),
        Err(RenderError::Decode(DecodeError::Unsupported(_)))
    ));
    // A truncated JPEG either decodes what is there or is refused; it never panics.
    let _ = render::render(&data("truncated.jpg"), 128);
    for cut in [10usize, 100, 1000] {
        let b = data("lossy.webp");
        let _ = render::render(&b[..cut.min(b.len())], 128);
        let p = data("palette.png");
        let _ = render::render(&p[..cut.min(p.len())], 128);
    }
}

#[test]
fn a_decompression_bomb_is_refused_before_decoding() {
    // A 10000 x 10000 one-bit PNG is a few kilobytes on disk and 100 megapixels once decoded.
    let mut png = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut png, 10_000, 10_000);
        enc.set_color(png::ColorType::Grayscale);
        enc.set_depth(png::BitDepth::One);
        let mut w = enc.write_header().unwrap();
        w.write_image_data(&vec![0u8; 1250 * 10_000]).unwrap();
    }
    assert!(png.len() < 1 << 20, "{} bytes", png.len());
    assert!(matches!(
        render::render(&png, 128),
        Err(RenderError::Decode(DecodeError::TooLarge(_)))
    ));
}

#[test]
fn random_mutations_never_panic() {
    let mut seed = 12345u32;
    let mut rnd = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    for name in [
        "photo.jpg",
        "palette.png",
        "anim.gif",
        "lossy.webp",
        "alpha.webp",
        "orient6.jpg",
    ] {
        let original = data(name);
        for _ in 0..60 {
            let mut b = original.clone();
            for _ in 0..(1 + rnd() % 8) {
                let i = (rnd() as usize) % b.len();
                b[i] = rnd() as u8;
            }
            let r = std::panic::catch_unwind(|| render::render(&b, 64));
            assert!(r.is_ok(), "{name} panicked on a mutated input");
        }
    }
}
