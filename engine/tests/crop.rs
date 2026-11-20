//! Pixel-exact crop, through the C ABI.

mod support;

use std::ptr;

use snapit_engine::{
    SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, snapit_buffer_free, snapit_crop,
};
use support::{alloc, fixture_bgra, fixture_rgb};

const SRC_W: u32 = 301;
const SRC_H: u32 = 187;
/// 301 * 4 = 1204; the stride is wider, like a ScreenCaptureKit buffer's.
const SRC_STRIDE: usize = 1204 + 96;
const PADDING: u8 = 0xAB;

fn crop(
    src: &[u8],
    src_size: (u32, u32),
    src_stride: usize,
    rect: (u32, u32, u32, u32),
    dst: &mut [u8],
    dst_stride: usize,
) -> i32 {
    let (x, y, w, h) = rect;
    unsafe {
        snapit_crop(
            src.as_ptr(),
            src_size.0,
            src_size.1,
            src_stride,
            x,
            y,
            w,
            h,
            dst.as_mut_ptr(),
            dst_stride,
        )
    }
}

/// Crops the fixture and checks every destination pixel against the fixture formula evaluated at
/// the source coordinate, and every padding byte for being left alone.
fn check_crop(rect: (u32, u32, u32, u32), dst_stride: usize) {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let (x, y, w, h) = rect;
    let mut dst = vec![PADDING; dst_stride * h as usize];
    assert_eq!(
        crop(&src, (SRC_W, SRC_H), SRC_STRIDE, rect, &mut dst, dst_stride),
        SNAPIT_STATUS_OK,
        "{rect:?}"
    );
    for row in 0..h {
        for col in 0..w {
            let [r, g, b] = fixture_rgb(x + col, y + row, SRC_W, SRC_H);
            let at = row as usize * dst_stride + col as usize * 4;
            assert_eq!(
                dst[at..at + 4],
                [b, g, r, 255],
                "pixel {col},{row} of {rect:?}"
            );
        }
        let pad = row as usize * dst_stride + w as usize * 4;
        assert!(
            dst[pad..(row as usize + 1) * dst_stride]
                .iter()
                .all(|&b| b == PADDING),
            "row {row} padding of {rect:?} was written"
        );
    }
}

#[test]
fn every_pixel_of_an_interior_rectangle_is_the_source_pixel() {
    check_crop((37, 19, 101, 53), 101 * 4);
}

#[test]
fn the_destination_stride_may_be_wider_than_the_row_and_its_padding_stays_untouched() {
    check_crop((37, 19, 101, 53), 101 * 4 + 60);
}

#[test]
fn the_rectangle_may_touch_every_edge_of_the_source() {
    for rect in [
        (0, 0, SRC_W, SRC_H),
        (0, 0, 1, 1),
        (SRC_W - 1, SRC_H - 1, 1, 1),
        (SRC_W - 1, 0, 1, SRC_H),
        (0, SRC_H - 1, SRC_W, 1),
        (200, 100, SRC_W - 200, SRC_H - 100),
    ] {
        check_crop(rect, rect.2 as usize * 4 + 16);
    }
}

#[test]
fn an_odd_width_and_height_are_not_rounded() {
    check_crop((3, 5, 7, 11), 7 * 4);
    check_crop((299, 185, 2, 2), 2 * 4);
}

#[test]
fn cropping_a_crop_equals_cropping_once() {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let (stride_a, stride_b) = (120 * 4 + 32, 40 * 4);
    let mut first = vec![0u8; stride_a * 90];
    assert_eq!(
        crop(
            &src,
            (SRC_W, SRC_H),
            SRC_STRIDE,
            (10, 20, 120, 90),
            &mut first,
            stride_a
        ),
        SNAPIT_STATUS_OK
    );
    let mut second = vec![0u8; stride_b * 30];
    assert_eq!(
        crop(
            &first,
            (120, 90),
            stride_a,
            (15, 25, 40, 30),
            &mut second,
            stride_b
        ),
        SNAPIT_STATUS_OK
    );
    let mut once = vec![0u8; stride_b * 30];
    assert_eq!(
        crop(
            &src,
            (SRC_W, SRC_H),
            SRC_STRIDE,
            (25, 45, 40, 30),
            &mut once,
            stride_b
        ),
        SNAPIT_STATUS_OK
    );
    assert_eq!(second, once);
}

#[test]
fn it_crops_between_engine_buffers_whose_strides_the_engine_chose() {
    let mut source = alloc(SRC_W, SRC_H);
    let pixels = fixture_bgra(SRC_W, SRC_H, source.stride);
    unsafe { ptr::copy_nonoverlapping(pixels.as_ptr(), source.data, pixels.len()) };
    let mut out = alloc(64, 48);

    let status = unsafe {
        snapit_crop(
            source.data,
            source.width,
            source.height,
            source.stride,
            100,
            60,
            64,
            48,
            out.data,
            out.stride,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    for row in 0..48u32 {
        for col in 0..64u32 {
            let [r, g, b] = fixture_rgb(100 + col, 60 + row, SRC_W, SRC_H);
            let at = row as usize * out.stride + col as usize * 4;
            let got = unsafe { std::slice::from_raw_parts(out.data.add(at), 4) };
            assert_eq!(got, [b, g, r, 255], "pixel {col},{row}");
        }
    }
    assert_eq!(
        (out.width, out.height),
        (64, 48),
        "bookkeeping is untouched"
    );
    unsafe {
        snapit_buffer_free(&mut source);
        snapit_buffer_free(&mut out);
    }
}

#[test]
fn a_refused_crop_writes_nothing() {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    type Rect = (u32, u32, u32, u32);
    let refused: &[(&str, Rect)] = &[
        ("zero width", (0, 0, 0, 10)),
        ("zero height", (0, 0, 10, 0)),
        ("past the right edge", (SRC_W - 9, 0, 10, 10)),
        ("past the bottom edge", (0, SRC_H - 9, 10, 10)),
        ("origin outside", (SRC_W, 0, 1, 1)),
        ("x + width wraps u32", (u32::MAX, 0, 2, 1)),
        ("width wraps u32", (1, 0, u32::MAX, 1)),
        ("y + height wraps u32", (0, u32::MAX, 1, 2)),
    ];
    for (name, rect) in refused {
        let mut dst = vec![PADDING; 64 * 4 * 64];
        let status = crop(&src, (SRC_W, SRC_H), SRC_STRIDE, *rect, &mut dst, 64 * 4);
        assert_eq!(status, SNAPIT_STATUS_INVALID_ARGUMENT, "{name}");
        assert!(dst.iter().all(|&b| b == PADDING), "{name} wrote");
    }
}

#[test]
fn bad_strides_and_pointers_are_refused() {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let mut dst = vec![PADDING; 64 * 4 * 64];

    // The destination stride cannot hold a row.
    assert_eq!(
        crop(
            &src,
            (SRC_W, SRC_H),
            SRC_STRIDE,
            (0, 0, 64, 64),
            &mut dst,
            64 * 4 - 1
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    // The source stride cannot hold a source row.
    assert_eq!(
        crop(
            &src,
            (SRC_W, SRC_H),
            301 * 4 - 1,
            (0, 0, 64, 64),
            &mut dst,
            64 * 4
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    // A stride so large the span overflows.
    assert_eq!(
        crop(
            &src,
            (SRC_W, SRC_H),
            usize::MAX / 2,
            (0, 0, 64, 64),
            &mut dst,
            64 * 4
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    unsafe {
        assert_eq!(
            snapit_crop(
                ptr::null(),
                SRC_W,
                SRC_H,
                SRC_STRIDE,
                0,
                0,
                8,
                8,
                dst.as_mut_ptr(),
                32
            ),
            SNAPIT_STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            snapit_crop(
                src.as_ptr(),
                SRC_W,
                SRC_H,
                SRC_STRIDE,
                0,
                0,
                8,
                8,
                ptr::null_mut(),
                32
            ),
            SNAPIT_STATUS_INVALID_ARGUMENT
        );
    }
    assert!(dst.iter().all(|&b| b == PADDING));
}

#[test]
fn overlapping_images_are_refused() {
    let mut image = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let before = image.clone();
    let base = image.as_mut_ptr();
    // A crop of the image into a rectangle of itself.
    let status = unsafe {
        snapit_crop(
            base,
            SRC_W,
            SRC_H,
            SRC_STRIDE,
            0,
            0,
            10,
            10,
            base.add(SRC_STRIDE * 50),
            10 * 4,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_INVALID_ARGUMENT);
    assert_eq!(image, before);
}
