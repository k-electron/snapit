//! Averaged-block pixelate, through the C ABI.

mod support;

use snapit_engine::{SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, snapit_pixelate};
use support::fixture_bgra;

const SRC_W: u32 = 301;
const SRC_H: u32 = 187;
/// 301 * 4 = 1204; the stride is wider, like a ScreenCaptureKit buffer's.
const SRC_STRIDE: usize = 1204 + 96;
const PADDING: u8 = 0xAB;

type Rect = (u32, u32, u32, u32);

fn pixelate(
    src: &[u8],
    src_size: (u32, u32),
    src_stride: usize,
    rect: Rect,
    block: u32,
    dst: &mut [u8],
    dst_stride: usize,
) -> i32 {
    let (x, y, w, h) = rect;
    unsafe {
        snapit_pixelate(
            src.as_ptr(),
            src_size.0,
            src_size.1,
            src_stride,
            x,
            y,
            w,
            h,
            block,
            dst.as_mut_ptr(),
            dst_stride,
        )
    }
}

/// What every pixel of the rectangle must be, worked out here and not by the engine: the grid of
/// `block` x `block` tiles starts at the rectangle's top left, a tile cut off by the rectangle's
/// right or bottom edge is smaller, and every pixel of a tile is the floored mean of the tile's
/// source pixels, channel by channel (all four, alpha included).
fn expected(src: &[u8], stride: usize, rect: Rect, block: u32) -> Vec<[u8; 4]> {
    let (x, y, w, h) = rect;
    let mut out = vec![[0u8; 4]; (w * h) as usize];
    for ty in (0..h).step_by(block as usize) {
        for tx in (0..w).step_by(block as usize) {
            let (tw, th) = (block.min(w - tx), block.min(h - ty));
            let mut sum = [0u64; 4];
            for row in 0..th {
                for col in 0..tw {
                    let at = (y + ty + row) as usize * stride + (x + tx + col) as usize * 4;
                    for (c, total) in sum.iter_mut().enumerate() {
                        *total += u64::from(src[at + c]);
                    }
                }
            }
            let n = u64::from(tw) * u64::from(th);
            let mean = [0, 1, 2, 3].map(|c| (sum[c] / n) as u8);
            for row in 0..th {
                for col in 0..tw {
                    out[((ty + row) * w + tx + col) as usize] = mean;
                }
            }
        }
    }
    out
}

/// Pixelates a rectangle of the fixture into a destination with its own stride and checks every
/// pixel against the independently computed means, the destination's padding for being left
/// alone and the source for being unchanged.
fn check(rect: Rect, block: u32, dst_stride: usize) {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let original = src.clone();
    let (_, _, w, h) = rect;
    let mut dst = vec![PADDING; dst_stride * h as usize];
    assert_eq!(
        pixelate(
            &src,
            (SRC_W, SRC_H),
            SRC_STRIDE,
            rect,
            block,
            &mut dst,
            dst_stride
        ),
        SNAPIT_STATUS_OK,
        "{rect:?} block {block}"
    );
    let want = expected(&src, SRC_STRIDE, rect, block);
    for row in 0..h {
        for col in 0..w {
            let at = row as usize * dst_stride + col as usize * 4;
            assert_eq!(
                dst[at..at + 4],
                want[(row * w + col) as usize],
                "pixel {col},{row} of {rect:?} block {block}"
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
    assert_eq!(src, original, "the source was changed");
}

#[test]
fn every_pixel_of_a_whole_number_of_blocks_is_its_blocks_mean() {
    check((40, 24, 64, 48), 16, 64 * 4);
}

#[test]
fn edge_blocks_are_smaller_and_averaged_over_their_own_pixels() {
    // 101 x 53 with 16-pixel blocks: the last column of blocks is 5 wide, the last row 5 tall.
    check((37, 19, 101, 53), 16, 101 * 4);
}

#[test]
fn a_rectangle_on_the_images_right_and_bottom_edge() {
    check((SRC_W - 50, SRC_H - 30, 50, 30), 12, 50 * 4);
}

#[test]
fn the_whole_image_in_one_call() {
    check((0, 0, SRC_W, SRC_H), 24, SRC_W as usize * 4);
}

#[test]
fn the_destination_stride_may_be_wider_than_the_row_and_its_padding_stays_untouched() {
    check((10, 10, 33, 21), 8, 33 * 4 + 52);
}

#[test]
fn a_block_bigger_than_the_rectangle_averages_the_whole_rectangle() {
    check((20, 20, 30, 18), 4000, 30 * 4);
}

#[test]
fn a_block_of_one_pixel_copies_the_pixels() {
    check((5, 5, 17, 9), 1, 17 * 4);
}

#[test]
fn a_one_pixel_rectangle_is_that_pixel() {
    check((100, 100, 1, 1), 16, 4);
}

#[test]
fn a_window_of_a_bigger_image_reads_and_writes_through_its_own_strides() {
    // The Editor pixelates from a window of the Capture (the crop) into a window of its Export
    // buffer: the same call with pointers moved to the windows' top left corners.
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let (wx, wy, ww, wh) = (30u32, 20u32, 200u32, 120u32);
    let window = &src[wy as usize * SRC_STRIDE + wx as usize * 4..];
    let rect = (13, 9, 77, 41);
    let mut dst = vec![PADDING; 400 * 4 * 80];
    let dst_stride = 400 * 4;
    let status = unsafe {
        snapit_pixelate(
            window.as_ptr(),
            ww,
            wh,
            SRC_STRIDE,
            rect.0,
            rect.1,
            rect.2,
            rect.3,
            16,
            dst.as_mut_ptr().add(5 * dst_stride + 7 * 4),
            dst_stride,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    // The same Redaction on the whole image: its rectangle shifted by the window's origin.
    let want = expected(
        &src,
        SRC_STRIDE,
        (wx + rect.0, wy + rect.1, rect.2, rect.3),
        16,
    );
    for row in 0..rect.3 {
        for col in 0..rect.2 {
            let at = (5 + row as usize) * dst_stride + (7 + col as usize) * 4;
            assert_eq!(
                dst[at..at + 4],
                want[(row * rect.2 + col) as usize],
                "pixel {col},{row}"
            );
        }
    }
    let untouched = dst.iter().filter(|&&b| b == PADDING).count();
    assert_eq!(
        untouched,
        dst.len() - (rect.2 * rect.3 * 4) as usize,
        "only the rectangle was written"
    );
}

#[test]
fn the_same_call_twice_gives_the_same_pixels() {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let mut a = vec![0u8; 90 * 4 * 60];
    let mut b = vec![0u8; 90 * 4 * 60];
    for dst in [&mut a, &mut b] {
        assert_eq!(
            pixelate(
                &src,
                (SRC_W, SRC_H),
                SRC_STRIDE,
                (3, 4, 90, 60),
                14,
                dst,
                90 * 4
            ),
            SNAPIT_STATUS_OK
        );
    }
    assert_eq!(a, b);
}

/// Every invalid call must say so and write nothing.
fn check_invalid(rect: Rect, block: u32, src_stride: usize, dst_stride: usize) {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let mut dst = vec![PADDING; 400 * 400 * 4];
    let status = pixelate(
        &src,
        (SRC_W, SRC_H),
        src_stride,
        rect,
        block,
        &mut dst,
        dst_stride,
    );
    assert_eq!(
        status, SNAPIT_STATUS_INVALID_ARGUMENT,
        "{rect:?} block {block}"
    );
    assert!(
        dst.iter().all(|&b| b == PADDING),
        "{rect:?} wrote to the destination"
    );
}

#[test]
fn zero_sizes_and_a_zero_block_are_refused() {
    check_invalid((0, 0, 0, 10), 8, SRC_STRIDE, 400 * 4);
    check_invalid((0, 0, 10, 0), 8, SRC_STRIDE, 400 * 4);
    check_invalid((0, 0, 10, 10), 0, SRC_STRIDE, 400 * 4);
}

#[test]
fn a_rectangle_outside_the_image_is_refused() {
    check_invalid((SRC_W - 9, 0, 10, 10), 8, SRC_STRIDE, 400 * 4);
    check_invalid((0, SRC_H - 9, 10, 10), 8, SRC_STRIDE, 400 * 4);
    check_invalid((SRC_W, 0, 1, 1), 8, SRC_STRIDE, 400 * 4);
}

#[test]
fn sums_that_would_wrap_are_refused() {
    check_invalid((u32::MAX, 0, 2, 10), 8, SRC_STRIDE, 400 * 4);
    check_invalid((0, u32::MAX, 10, 2), 8, SRC_STRIDE, 400 * 4);
    check_invalid((0, 0, u32::MAX, u32::MAX), 8, SRC_STRIDE, 400 * 4);
}

#[test]
fn a_stride_smaller_than_a_row_is_refused() {
    check_invalid((0, 0, 10, 10), 8, 1203, 400 * 4);
    check_invalid((0, 0, 10, 10), 8, SRC_STRIDE, 39);
}

#[test]
fn null_pointers_are_refused() {
    let src = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let mut dst = vec![PADDING; 64 * 64 * 4];
    unsafe {
        assert_eq!(
            snapit_pixelate(
                std::ptr::null(),
                SRC_W,
                SRC_H,
                SRC_STRIDE,
                0,
                0,
                8,
                8,
                4,
                dst.as_mut_ptr(),
                32
            ),
            SNAPIT_STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            snapit_pixelate(
                src.as_ptr(),
                SRC_W,
                SRC_H,
                SRC_STRIDE,
                0,
                0,
                8,
                8,
                4,
                std::ptr::null_mut(),
                32
            ),
            SNAPIT_STATUS_INVALID_ARGUMENT
        );
    }
    assert!(dst.iter().all(|&b| b == PADDING));
}

#[test]
fn overlapping_source_and_destination_are_refused() {
    let mut image = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    let original = image.clone();
    let base = image.as_mut_ptr();
    unsafe {
        // The destination inside the source image.
        let inside = snapit_pixelate(
            base,
            SRC_W,
            SRC_H,
            SRC_STRIDE,
            0,
            0,
            16,
            16,
            8,
            base.add(40 * SRC_STRIDE),
            64,
        );
        assert_eq!(inside, SNAPIT_STATUS_INVALID_ARGUMENT);
        // The same buffer, in place.
        let same = snapit_pixelate(
            base, SRC_W, SRC_H, SRC_STRIDE, 0, 0, 16, 16, 8, base, SRC_STRIDE,
        );
        assert_eq!(same, SNAPIT_STATUS_INVALID_ARGUMENT);
    }
    assert_eq!(image, original, "a refused call changed the image");
}

#[test]
fn a_buffer_right_after_the_source_is_not_an_overlap() {
    // One allocation holding the source and, right after it, the destination: they touch, they
    // do not overlap.
    let src_len = SRC_STRIDE * (SRC_H as usize - 1) + SRC_W as usize * 4;
    let mut both = fixture_bgra(SRC_W, SRC_H, SRC_STRIDE);
    both.resize(src_len + 16 * 4 * 16, PADDING);
    let base = both.as_mut_ptr();
    let status = unsafe {
        snapit_pixelate(
            base,
            SRC_W,
            SRC_H,
            SRC_STRIDE,
            0,
            0,
            16,
            16,
            8,
            base.add(src_len),
            16 * 4,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
}

#[test]
fn no_source_pixel_survives_where_a_block_holds_different_pixels() {
    // Two columns, black and white: every 2 x 2 block is a mean no source pixel has.
    let stride = 8 * 4;
    let mut src = vec![0u8; stride * 4];
    for row in 0..4 {
        for col in 0..8 {
            let value = if col % 2 == 0 { 0 } else { 254 };
            let at = row * stride + col * 4;
            src[at..at + 4].copy_from_slice(&[value, value, value, 255]);
        }
    }
    let mut dst = vec![0u8; stride * 4];
    assert_eq!(
        pixelate(&src, (8, 4), stride, (0, 0, 8, 4), 2, &mut dst, stride),
        SNAPIT_STATUS_OK
    );
    for pixel in dst.as_chunks::<4>().0 {
        assert_eq!(*pixel, [127, 127, 127, 255]);
    }
}

#[test]
fn a_rectangle_of_more_pixels_than_any_display_is_refused_before_it_is_read() {
    // 2^21 x 2^20 pixels claimed over a few bytes: the size check refuses it, nothing is read.
    let src = [0u8; 64];
    let mut dst = [PADDING; 64];
    let status = unsafe {
        snapit_pixelate(
            src.as_ptr(),
            1 << 21,
            1 << 20,
            (1usize << 21) * 4,
            0,
            0,
            1 << 21,
            1 << 20,
            8,
            dst.as_mut_ptr(),
            (1usize << 21) * 4,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_INVALID_ARGUMENT);
    assert!(dst.iter().all(|&b| b == PADDING));
}
