//! Shared helpers for the engine's C-ABI tests: fixture buffers and an independent PNG reader.
#![allow(dead_code)]

use std::io::Cursor;

use snapit_engine::{SNAPIT_STATUS_OK, SnapitBytes, SnapitPixelBuffer, snapit_buffer_alloc};

/// Colour of the fixture pixel at `(x, y)`: R follows x, G follows y, B is a checker. The
/// formula is the same one `scripts/run/png-inspect.swift` documents for the scripted run.
pub fn fixture_rgb(x: u32, y: u32, width: u32, height: u32) -> [u8; 3] {
    let r = (x * 255 / (width - 1).max(1)) as u8;
    let g = (y * 255 / (height - 1).max(1)) as u8;
    let b = if (x / 8 + y / 8).is_multiple_of(2) {
        40
    } else {
        200
    };
    [r, g, b]
}

/// A BGRA fixture image whose rows are `stride` bytes apart. The padding after each row is
/// filled with `0xEE` garbage that must never reach the PNG.
pub fn fixture_bgra(width: u32, height: u32, stride: usize) -> Vec<u8> {
    let mut data = vec![0xEE; stride * height as usize];
    for y in 0..height {
        for x in 0..width {
            let [r, g, b] = fixture_rgb(x, y, width, height);
            let at = y as usize * stride + x as usize * 4;
            data[at..at + 4].copy_from_slice(&[b, g, r, 255]);
        }
    }
    data
}

pub fn alloc(width: u32, height: u32) -> SnapitPixelBuffer {
    let mut buffer = SnapitPixelBuffer {
        data: std::ptr::null_mut(),
        width: 0,
        height: 0,
        stride: 0,
        mapped_len: 0,
    };
    assert_eq!(
        unsafe { snapit_buffer_alloc(width, height, &mut buffer) },
        SNAPIT_STATUS_OK
    );
    buffer
}

pub fn empty_bytes() -> SnapitBytes {
    SnapitBytes {
        data: std::ptr::null_mut(),
        len: 0,
        capacity: 0,
    }
}

pub fn bytes_of(bytes: &SnapitBytes) -> &[u8] {
    unsafe { std::slice::from_raw_parts(bytes.data, bytes.len) }
}

/// Every chunk's type and data, read by walking the file directly (no PNG decoder involved).
pub fn chunks(png: &[u8]) -> Vec<([u8; 4], Vec<u8>)> {
    assert_eq!(&png[..8], &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    let mut at = 8;
    let mut found = Vec::new();
    while at < png.len() {
        let len = u32::from_be_bytes(png[at..at + 4].try_into().unwrap()) as usize;
        let kind: [u8; 4] = png[at + 4..at + 8].try_into().unwrap();
        found.push((kind, png[at + 8..at + 8 + len].to_vec()));
        at += 12 + len;
    }
    found
}

pub fn chunk(png: &[u8], kind: &[u8; 4]) -> Option<Vec<u8>> {
    chunks(png)
        .into_iter()
        .find(|(k, _)| k == kind)
        .map(|(_, data)| data)
}

/// Decodes a PNG to tightly packed RGB8 plus its width and height.
pub fn decode_rgb(png: &[u8]) -> (Vec<u8>, u32, u32) {
    let decoder = png::Decoder::new(Cursor::new(png));
    let mut reader = decoder.read_info().unwrap();
    let mut pixels = vec![0; reader.output_buffer_size().unwrap()];
    let info = reader.next_frame(&mut pixels).unwrap();
    assert_eq!(info.color_type, png::ColorType::Rgb);
    assert_eq!(info.bit_depth, png::BitDepth::Eight);
    pixels.truncate(info.buffer_size());
    (pixels, info.width, info.height)
}
