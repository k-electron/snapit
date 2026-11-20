//! Averaged-block pixelate: what a Redaction does to the pixels beneath it.

use crate::buffer::SNAPIT_BYTES_PER_PIXEL;
use crate::{SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, SnapitStatus, guard};

/// The most pixels one call may cover. It keeps every per-channel sum of a tile (255 per pixel)
/// inside a `u64`, however large a caller claims its image is.
const MAX_PIXELS: u64 = 1 << 40;

/// The bytes a `width` x `height` image with `stride` bytes between rows spans: every row but
/// the last in full, the last up to its final pixel. `None` on overflow.
fn span(width: usize, height: usize, stride: usize) -> Option<usize> {
    let row = width.checked_mul(SNAPIT_BYTES_PER_PIXEL)?;
    stride.checked_mul(height - 1)?.checked_add(row)
}

/// Pixelates the `width` x `height` rectangle of a BGRA image that starts at column `x`, row
/// `y`, writing the result into `dst`: the rectangle is cut into square tiles of `block` pixels
/// with the first tile at the rectangle's top left corner, and every pixel of a tile becomes the
/// mean of the tile's source pixels, channel by channel (all four, rounded down). What is left at
/// the right and bottom edge, when the sides are not whole numbers of blocks, is folded into the
/// last tile of its row or column, so the edge tiles are between `block` and `2 * block - 1`
/// pixels on a side and never a thin strip or a lone pixel; a side shorter than one block is a
/// single tile. The result's top-left pixel is the pixelated source pixel `(x, y)`.
///
/// The source is never changed, so a caller can pixelate the same pixels again after the
/// destination has been drawn on, and Redactions that overlap each average the original
/// pixels. Both images are 8-bit BGRA, each read or written through its own stride (the
/// distance in bytes between the starts of two rows, at least `width * 4`); only the
/// `width * 4` pixel bytes of each destination row are written. `dst` may be the window of a
/// larger image (its pointer moved to the window's top left pixel, its stride the larger
/// image's), and so may `src`.
///
/// Returns `SNAPIT_STATUS_INVALID_ARGUMENT`, writing nothing, when a pointer is null, a size or
/// `block` is zero, a stride is too small, the rectangle is not wholly inside the source image,
/// the rectangle holds more than 2^40 pixels, or the two images overlap in memory.
///
/// # Safety
///
/// `src` must be valid for reads of `src_stride * (src_height - 1) + src_width * 4` bytes and
/// `dst` valid for writes of `dst_stride * (height - 1) + width * 4` bytes, for the whole call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_pixelate(
    src: *const u8,
    src_width: u32,
    src_height: u32,
    src_stride: usize,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    block: u32,
    dst: *mut u8,
    dst_stride: usize,
) -> SnapitStatus {
    guard(|| {
        if src.is_null() || dst.is_null() || width == 0 || height == 0 || block == 0 {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // The rectangle must lie inside the source: checked in u64 so no sum can wrap.
        let (rx, ry, w, h) = (
            u64::from(x),
            u64::from(y),
            u64::from(width),
            u64::from(height),
        );
        if rx + w > u64::from(src_width) || ry + h > u64::from(src_height) || w * h > MAX_PIXELS {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let row = w as usize * SNAPIT_BYTES_PER_PIXEL;
        if src_stride < src_width as usize * SNAPIT_BYTES_PER_PIXEL || dst_stride < row {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let (Some(src_span), Some(dst_span)) = (
            span(src_width as usize, src_height as usize, src_stride),
            span(w as usize, h as usize, dst_stride),
        ) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        let (src_start, dst_start) = (src as usize, dst as usize);
        if src_start < dst_start.saturating_add(dst_span)
            && dst_start < src_start.saturating_add(src_span)
        {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let (x, y, w, h, block) = (
            x as usize,
            y as usize,
            width as usize,
            height as usize,
            block as usize,
        );
        let mut ty = 0;
        while ty < h {
            let th = tile_len(h - ty, block);
            let mut tx = 0;
            while tx < w {
                let tw = tile_len(w - tx, block);
                // SAFETY: the caller guarantees both spans; the tile lies inside the rectangle,
                // which lies inside the source, and the spans do not overlap.
                unsafe {
                    let mean = tile_mean(
                        src.add((y + ty) * src_stride + (x + tx) * SNAPIT_BYTES_PER_PIXEL),
                        src_stride,
                        tw,
                        th,
                    );
                    fill_tile(
                        dst.add(ty * dst_stride + tx * SNAPIT_BYTES_PER_PIXEL),
                        dst_stride,
                        tw,
                        th,
                        mean,
                    );
                }
                tx += tw;
            }
            ty += th;
        }
        SNAPIT_STATUS_OK
    })
}

/// The length of the tile that starts where `remaining` pixels are left: `block`, except that a
/// leftover narrower than a block is folded into the tile before it (the last tile is then
/// between `block` and `2 * block - 1` long), so no tile is a sliver and no tile is a single
/// source pixel. A side shorter than one block is one tile.
fn tile_len(remaining: usize, block: usize) -> usize {
    if remaining < block.saturating_mul(2) {
        remaining
    } else {
        block
    }
}

/// The mean of a `tw` x `th` tile, rounded down, as four channel bytes.
///
/// # Safety
///
/// `at` must be valid for reads of the tile's rows, `stride` bytes apart.
unsafe fn tile_mean(at: *const u8, stride: usize, tw: usize, th: usize) -> [u8; 4] {
    let mut sum = [0u64; 4];
    for row in 0..th {
        // SAFETY: the caller guarantees the tile's rows.
        let pixels = unsafe { std::slice::from_raw_parts(at.add(row * stride), tw * 4) };
        for pixel in pixels.as_chunks::<4>().0 {
            sum[0] += u64::from(pixel[0]);
            sum[1] += u64::from(pixel[1]);
            sum[2] += u64::from(pixel[2]);
            sum[3] += u64::from(pixel[3]);
        }
    }
    let n = (tw * th) as u64;
    sum.map(|total| (total / n) as u8)
}

/// Writes `mean` over a `tw` x `th` tile.
///
/// # Safety
///
/// `at` must be valid for writes of the tile's rows, `stride` bytes apart.
unsafe fn fill_tile(at: *mut u8, stride: usize, tw: usize, th: usize, mean: [u8; 4]) {
    for row in 0..th {
        // SAFETY: the caller guarantees the tile's rows.
        let pixels = unsafe { std::slice::from_raw_parts_mut(at.add(row * stride), tw * 4) };
        for pixel in pixels.as_chunks_mut::<4>().0 {
            pixel.copy_from_slice(&mean);
        }
    }
}
