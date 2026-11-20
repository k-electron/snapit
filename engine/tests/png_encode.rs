//! PNG encoding through the C ABI: round trip, metadata and strides.

mod support;

use std::ptr;

use snapit_engine::{
    SNAPIT_PNG_BALANCED, SNAPIT_PNG_FAST, SNAPIT_PNG_HIGH, SNAPIT_STATUS_INVALID_ARGUMENT,
    SNAPIT_STATUS_OK, SnapitBytes, snapit_buffer_free, snapit_bytes_free, snapit_png_encode,
};
use support::{alloc, bytes_of, chunk, chunks, decode_rgb, empty_bytes, fixture_bgra, fixture_rgb};

/// Encodes `pixels` (a `width`, `height`, `stride` image) and returns the PNG bytes,
/// freeing the engine's copy.
fn encode(
    pixels: &[u8],
    (width, height, stride): (u32, u32, usize),
    level: u32,
    dpi: u32,
    icc: &[u8],
) -> Vec<u8> {
    let mut out = empty_bytes();
    let status = unsafe {
        snapit_png_encode(
            pixels.as_ptr(),
            width,
            height,
            stride,
            level,
            dpi,
            if icc.is_empty() {
                ptr::null()
            } else {
                icc.as_ptr()
            },
            icc.len(),
            &mut out,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let png = bytes_of(&out).to_vec();
    assert_eq!(unsafe { snapit_bytes_free(&mut out) }, SNAPIT_STATUS_OK);
    assert!(out.data.is_null());
    png
}

fn assert_matches_fixture(png: &[u8], width: u32, height: u32) {
    let (rgb, w, h) = decode_rgb(png);
    assert_eq!((w, h), (width, height));
    for y in 0..height {
        for x in 0..width {
            let at = (y * width + x) as usize * 3;
            assert_eq!(
                rgb[at..at + 3],
                fixture_rgb(x, y, width, height),
                "pixel {x},{y}"
            );
        }
    }
}

#[test]
fn a_tight_buffer_round_trips_pixel_exact_at_every_level() {
    let pixels = fixture_bgra(64, 48, 64 * 4);
    for level in [SNAPIT_PNG_FAST, SNAPIT_PNG_BALANCED, SNAPIT_PNG_HIGH] {
        let png = encode(&pixels, (64, 48, 256), level, 72, &[]);
        assert_matches_fixture(&png, 64, 48);
    }
}

#[test]
fn a_non_tight_stride_round_trips_and_padding_never_leaks() {
    // 301 px rows padded to 1216 bytes, the padding filled with 0xEE.
    let (w, h, stride) = (301, 187, 1216);
    let pixels = fixture_bgra(w, h, stride);
    let png = encode(&pixels, (w, h, stride), SNAPIT_PNG_FAST, 144, &[]);
    assert_matches_fixture(&png, w, h);
}

#[test]
fn an_engine_buffer_encodes_with_its_own_stride() {
    let mut buffer = alloc(333, 101);
    let fixture = fixture_bgra(333, 101, buffer.stride);
    unsafe { ptr::copy_nonoverlapping(fixture.as_ptr(), buffer.data, fixture.len()) };
    let mapped = unsafe { std::slice::from_raw_parts(buffer.data, buffer.stride * 101) };
    let png = encode(mapped, (333, 101, buffer.stride), SNAPIT_PNG_FAST, 144, &[]);
    assert_matches_fixture(&png, 333, 101);
    unsafe { snapit_buffer_free(&mut buffer) };
}

#[test]
fn phys_chunk_is_144_dpi_on_retina_and_72_dpi_at_1x() {
    let pixels = fixture_bgra(32, 32, 128);
    for (dpi, per_metre) in [(144u32, 5669u32), (72, 2835)] {
        let png = encode(&pixels, (32, 32, 128), SNAPIT_PNG_FAST, dpi, &[]);
        let phys = chunk(&png, b"pHYs").expect("pHYs chunk");
        assert_eq!(phys.len(), 9);
        assert_eq!(
            u32::from_be_bytes(phys[0..4].try_into().unwrap()),
            per_metre
        );
        assert_eq!(
            u32::from_be_bytes(phys[4..8].try_into().unwrap()),
            per_metre
        );
        assert_eq!(phys[8], 1, "unit is the metre");
    }
}

#[test]
fn the_icc_profile_is_embedded_byte_for_byte_and_no_srgb_chunk_competes() {
    let pixels = fixture_bgra(32, 32, 128);
    let profile: Vec<u8> = (0..1500u32).map(|i| (i * 7 % 251) as u8).collect();
    let png = encode(&pixels, (32, 32, 128), SNAPIT_PNG_FAST, 144, &profile);

    let names: Vec<[u8; 4]> = chunks(&png).into_iter().map(|(k, _)| k).collect();
    assert!(names.contains(b"iCCP"));
    assert!(!names.contains(b"sRGB") && !names.contains(b"gAMA"));

    // The decoder inflates the iCCP chunk for us.
    let decoder = png::Decoder::new(std::io::Cursor::new(&png[..]));
    let reader = decoder.read_info().unwrap();
    assert_eq!(reader.info().icc_profile.as_deref(), Some(&profile[..]));
}

#[test]
fn without_a_profile_no_color_chunks_are_written() {
    let pixels = fixture_bgra(8, 8, 32);
    let png = encode(&pixels, (8, 8, 32), SNAPIT_PNG_FAST, 72, &[]);
    let names: Vec<[u8; 4]> = chunks(&png).into_iter().map(|(k, _)| k).collect();
    assert!(!names.contains(b"iCCP") && !names.contains(b"sRGB"));
}

#[test]
fn invalid_arguments_come_back_as_status_codes() {
    let pixels = fixture_bgra(8, 8, 32);
    let mut out = empty_bytes();
    let p = pixels.as_ptr();
    let bad = SNAPIT_STATUS_INVALID_ARGUMENT;
    let call = |p: *const u8,
                size: (u32, u32, usize),
                level: u32,
                dpi: u32,
                icc_len: usize,
                out: *mut SnapitBytes| unsafe {
        snapit_png_encode(
            p,
            size.0,
            size.1,
            size.2,
            level,
            dpi,
            ptr::null(),
            icc_len,
            out,
        )
    };
    assert_eq!(call(ptr::null(), (8, 8, 32), 0, 72, 0, &mut out), bad);
    assert_eq!(call(p, (0, 8, 32), 0, 72, 0, &mut out), bad);
    assert_eq!(call(p, (8, 0, 32), 0, 72, 0, &mut out), bad);
    assert_eq!(
        call(p, (8, 8, 31), 0, 72, 0, &mut out),
        bad,
        "stride below a row"
    );
    assert_eq!(
        call(p, (8, 8, 32), 9, 72, 0, &mut out),
        bad,
        "unknown level"
    );
    assert_eq!(call(p, (8, 8, 32), 0, 0, 0, &mut out), bad, "zero dpi");
    assert_eq!(
        call(p, (8, 8, 32), 0, 72, 5, &mut out),
        bad,
        "icc length without icc"
    );
    assert_eq!(call(p, (8, 8, 32), 0, 72, 0, ptr::null_mut()), bad);
    assert_eq!(
        call(p, (u32::MAX, u32::MAX, usize::MAX), 0, 72, 0, &mut out),
        bad,
        "size overflow"
    );
    assert!(
        out.data.is_null(),
        "a refused call leaves the output untouched"
    );
}

#[test]
fn freeing_empty_bytes_is_harmless() {
    let mut out = empty_bytes();
    assert_eq!(unsafe { snapit_bytes_free(&mut out) }, SNAPIT_STATUS_OK);
    assert_eq!(
        unsafe { snapit_bytes_free(ptr::null_mut()) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
}
