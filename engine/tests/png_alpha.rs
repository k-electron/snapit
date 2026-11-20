//! Transparent pixels (a Window Capture's rounded corners) through the C ABI: the engine's pixels
//! are premultiplied BGRA, a PNG holds straight (un-premultiplied) RGBA, and an image with no
//! transparent pixel stays a plain RGB PNG.

mod support;

use std::io::Cursor;
use std::ptr;

use snapit_engine::{
    SNAPIT_PNG_BALANCED, SNAPIT_PNG_FAST, SNAPIT_STATUS_OK, SnapitPngParams, snapit_buffer_free,
    snapit_bytes_free, snapit_crop, snapit_downscale, snapit_pixelate, snapit_png_encode,
    snapit_png_encode_ex, snapit_png_encode_to_fd,
};
use support::{alloc, bytes_of, chunk, empty_bytes, fixture_bgra};

/// A BGRA image: `pixel(x, y)` gives the premultiplied `[b, g, r, a]`.
fn image(
    width: u32,
    height: u32,
    stride: usize,
    mut pixel: impl FnMut(u32, u32) -> [u8; 4],
) -> Vec<u8> {
    let mut data = vec![0xEE; stride * height as usize];
    for y in 0..height {
        for x in 0..width {
            let at = y as usize * stride + x as usize * 4;
            data[at..at + 4].copy_from_slice(&pixel(x, y));
        }
    }
    data
}

fn params(level: u32, (out_width, out_height): (u32, u32)) -> SnapitPngParams {
    SnapitPngParams {
        level,
        dpi: 144,
        out_width,
        out_height,
        icc: ptr::null(),
        icc_len: 0,
    }
}

fn encode(pixels: &[u8], (w, h, stride): (u32, u32, usize), p: &SnapitPngParams) -> Vec<u8> {
    let mut out = empty_bytes();
    let status = unsafe { snapit_png_encode_ex(pixels.as_ptr(), w, h, stride, p, &mut out) };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let png = bytes_of(&out).to_vec();
    unsafe { snapit_bytes_free(&mut out) };
    png
}

/// The PNG's colour type byte, read from its header chunk (2 is RGB, 6 is RGBA).
fn color_type(png: &[u8]) -> u8 {
    chunk(png, b"IHDR").unwrap()[9]
}

/// Decodes any 8-bit RGB or RGBA PNG to RGBA, plus the colour type it was stored as.
fn decode_rgba(png: &[u8]) -> (Vec<[u8; 4]>, u32, u32, u8) {
    let mut reader = png::Decoder::new(Cursor::new(png)).read_info().unwrap();
    let mut buffer = vec![0; reader.output_buffer_size().unwrap()];
    let info = reader.next_frame(&mut buffer).unwrap();
    let stored = color_type(png);
    let channels = if stored == 6 { 4 } else { 3 };
    let pixels = buffer[..info.buffer_size()]
        .chunks(channels)
        .map(|p| [p[0], p[1], p[2], if channels == 4 { p[3] } else { 255 }])
        .collect();
    (pixels, info.width, info.height, stored)
}

/// A 40 x 30 window: transparent corners (a 6 px quarter-square cut), a half-transparent edge
/// column, and the fixture's colours inside.
fn window(stride: usize) -> Vec<u8> {
    image(40, 30, stride, |x, y| {
        let corner = !(6..34).contains(&x) && !(6..24).contains(&y);
        if corner {
            return [0, 0, 0, 0];
        }
        let [r, g, b] = support::fixture_rgb(x, y, 40, 30);
        if x == 20 {
            // 50% alpha, premultiplied: each channel halved (rounded down).
            return [b / 2, g / 2, r / 2, 128];
        }
        [b, g, r, 255]
    })
}

#[test]
fn an_image_with_no_transparent_pixel_stays_an_rgb_png() {
    let pixels = fixture_bgra(64, 48, 256);
    let png = encode(&pixels, (64, 48, 256), &params(SNAPIT_PNG_FAST, (64, 48)));
    assert_eq!(color_type(&png), 2);
}

#[test]
fn transparent_corners_make_an_rgba_png_with_exact_alpha_and_straight_colour() {
    let pixels = window(160);
    for level in [SNAPIT_PNG_FAST, SNAPIT_PNG_BALANCED] {
        let png = encode(&pixels, (40, 30, 160), &params(level, (40, 30)));
        let (rgba, w, h, stored) = decode_rgba(&png);
        assert_eq!((w, h, stored), (40, 30, 6));
        let at = |x: u32, y: u32| rgba[(y * 40 + x) as usize];
        // Fully transparent corners, in all four.
        for (x, y) in [(0, 0), (39, 0), (0, 29), (39, 29), (5, 5), (34, 24)] {
            assert_eq!(at(x, y)[3], 0, "corner {x},{y}");
        }
        // The first opaque pixel next to a corner is exact.
        let [r, g, b] = support::fixture_rgb(6, 0, 40, 30);
        assert_eq!(at(6, 0), [r, g, b, 255]);
        let [r, g, b] = support::fixture_rgb(10, 15, 40, 30);
        assert_eq!(at(10, 15), [r, g, b, 255]);
        // Half alpha: the colour is un-premultiplied back to the fixture's, within what 8-bit
        // premultiplied storage keeps (one step of the premultiplied value is about two steps here).
        let [r, g, b] = support::fixture_rgb(20, 15, 40, 30);
        let got = at(20, 15);
        assert_eq!(got[3], 128);
        for (c, want) in got[..3].iter().zip([r, g, b]) {
            assert!(
                (i32::from(*c) - i32::from(want)).abs() <= 2,
                "{got:?} vs {want}"
            );
        }
    }
}

#[test]
fn the_legacy_entry_point_and_a_file_stream_make_the_same_rgba_png() {
    let pixels = window(160);
    let want = encode(&pixels, (40, 30, 160), &params(SNAPIT_PNG_FAST, (40, 30)));

    let mut out = empty_bytes();
    let status = unsafe {
        snapit_png_encode(
            pixels.as_ptr(),
            40,
            30,
            160,
            SNAPIT_PNG_FAST,
            144,
            ptr::null(),
            0,
            &mut out,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    assert_eq!(color_type(bytes_of(&out)), 6);
    unsafe { snapit_bytes_free(&mut out) };

    let path = std::env::temp_dir().join(format!("snapit-alpha-{}.png", std::process::id()));
    let file = std::fs::File::create(&path).unwrap();
    use std::os::fd::AsRawFd;
    let p = params(SNAPIT_PNG_FAST, (40, 30));
    let status =
        unsafe { snapit_png_encode_to_fd(pixels.as_ptr(), 40, 30, 160, &p, file.as_raw_fd()) };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let streamed = std::fs::read(&path).unwrap();
    std::fs::remove_file(&path).unwrap();
    assert_eq!(streamed, want);
}

#[test]
fn a_1x_average_weights_colour_by_alpha() {
    // One opaque red pixel and three transparent ones average to a quarter-covered red: the
    // premultiplied average is (64, 0, 0, 64) and the straight colour is full red at alpha 64.
    // A straight-colour average would give a dark red (r 64) instead.
    let pixels = image(2, 2, 8, |x, y| {
        if (x, y) == (0, 0) {
            [0, 0, 255, 255]
        } else {
            [0, 0, 0, 0]
        }
    });
    let png = encode(&pixels, (2, 2, 8), &params(SNAPIT_PNG_FAST, (1, 1)));
    let (rgba, ..) = decode_rgba(&png);
    assert_eq!(rgba, vec![[255, 0, 0, 64]]);
}

#[test]
fn a_1x_average_of_a_window_keeps_its_corners_clear_and_its_middle_opaque() {
    // 2x the window above: every pixel doubled in both directions.
    let small = window(160);
    let pixels = image(80, 60, 320, |x, y| {
        let at = (y / 2) as usize * 160 + (x / 2) as usize * 4;
        [small[at], small[at + 1], small[at + 2], small[at + 3]]
    });
    let png = encode(
        &pixels,
        (80, 60, 320),
        &params(SNAPIT_PNG_BALANCED, (40, 30)),
    );
    let (rgba, w, h, stored) = decode_rgba(&png);
    assert_eq!((w, h, stored), (40, 30, 6));
    assert_eq!(rgba[0][3], 0);
    assert_eq!(rgba[(29 * 40 + 39) as usize][3], 0);
    assert_eq!(rgba[(15 * 40 + 10) as usize][3], 255);
    // Doubled pixels average to themselves: the downscale is exactly the small window.
    let (direct, ..) = decode_rgba(&encode(
        &window(160),
        (40, 30, 160),
        &params(SNAPIT_PNG_BALANCED, (40, 30)),
    ));
    assert_eq!(rgba, direct);
}

#[test]
fn a_crop_copies_alpha_bytes_untouched() {
    // The window's transparent corner and half-alpha column survive an Area-style crop.
    let pixels = window(160);
    let mut dst = alloc(12, 8);
    let status = unsafe {
        snapit_crop(
            pixels.as_ptr(),
            40,
            30,
            160,
            16,
            0,
            12,
            8,
            dst.data,
            dst.stride,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let out = unsafe { std::slice::from_raw_parts(dst.data, dst.stride * 8) };
    for y in 0..8usize {
        for x in 0..12usize {
            let from = y * 160 + (x + 16) * 4;
            let to = y * dst.stride + x * 4;
            assert_eq!(out[to..to + 4], pixels[from..from + 4], "pixel {x},{y}");
        }
    }
    // Column 20 (4 in the crop) has half alpha.
    assert_eq!(out[4 * 4 + 3], 128);
    unsafe { snapit_buffer_free(&mut dst) };
}

#[test]
fn a_redaction_over_a_transparent_corner_averages_premultiplied_pixels() {
    // The window's top-left 8 x 8 tile: 6 x 6 pixels are the transparent corner, the rest is
    // opaque. The tile's mean is premultiplied, so it keeps a quarter-ish alpha, never an
    // opaque colour next to a transparent one.
    let pixels = window(160);
    let mut dst = alloc(8, 8);
    let status = unsafe {
        snapit_pixelate(
            pixels.as_ptr(),
            40,
            30,
            160,
            0,
            0,
            8,
            8,
            8,
            dst.data,
            dst.stride,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let out = unsafe { std::slice::from_raw_parts(dst.data, dst.stride * 8) }.to_vec();
    unsafe { snapit_buffer_free(&mut dst) };
    // 64 pixels, 28 of them opaque (the corner square is 6 x 6 = 36 transparent).
    let expected_alpha = (28 * 255 / 64) as u8;
    for y in 0..8usize {
        for x in 0..8usize {
            assert_eq!(out[y * dst_stride_of(8) + x * 4 + 3], expected_alpha);
        }
    }
    // Encoding it gives an RGBA PNG with that alpha and a straight colour no brighter than 255.
    let tile = image(8, 8, 32, |x, y| {
        let at = y as usize * dst_stride_of(8) + x as usize * 4;
        [out[at], out[at + 1], out[at + 2], out[at + 3]]
    });
    let png = encode(&tile, (8, 8, 32), &params(SNAPIT_PNG_FAST, (8, 8)));
    let (rgba, _, _, stored) = decode_rgba(&png);
    assert_eq!(stored, 6);
    assert!(rgba.iter().all(|p| p[3] == expected_alpha));
}

/// The stride the engine gives a buffer `width` pixels wide.
fn dst_stride_of(width: usize) -> usize {
    (width * 4).next_multiple_of(64)
}

#[test]
fn a_thumbnail_keeps_the_averaged_alpha() {
    let pixels = image(2, 2, 8, |x, y| {
        if (x, y) == (0, 0) {
            [0, 0, 255, 255]
        } else {
            [0, 0, 0, 0]
        }
    });
    let mut dst = alloc(1, 1);
    let status =
        unsafe { snapit_downscale(pixels.as_ptr(), 2, 2, 8, 1, 1, dst.data, dst.stride, 0) };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let out = unsafe { std::slice::from_raw_parts(dst.data, 4) }.to_vec();
    unsafe { snapit_buffer_free(&mut dst) };
    // Premultiplied BGRA: the same average the PNG path starts from.
    assert_eq!(out, vec![0, 0, 64, 64]);
}

#[test]
fn a_big_incompressible_rgba_image_encodes_at_the_fast_level() {
    // Noise does not compress: the output buffer must hold a raw RGBA frame.
    let (w, h) = (900u32, 700u32);
    let mut state = 0x2545_F491_4F6C_DD1Du64;
    let pixels = image(w, h, w as usize * 4, |x, _| {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let a = if x == 0 { 0 } else { 200 };
        let c = |shift: u32| ((state >> shift) as u8).min(a);
        [c(0), c(8), c(16), a]
    });
    let png = encode(
        &pixels,
        (w, h, w as usize * 4),
        &params(SNAPIT_PNG_FAST, (w, h)),
    );
    let (rgba, ow, oh, stored) = decode_rgba(&png);
    assert_eq!((ow, oh, stored), (w, h, 6));
    assert_eq!(rgba[0][3], 0);
}
