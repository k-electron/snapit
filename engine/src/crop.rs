//! Pixel-exact crop: copies a rectangle of a BGRA image into another buffer.

use std::ptr;

use crate::buffer::SNAPIT_BYTES_PER_PIXEL;
use crate::{SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, SnapitStatus, guard};

/// The bytes a `width` x `height` image with `stride` bytes between rows spans: every row but
/// the last in full, the last up to its final pixel. `None` on overflow.
fn span(width: usize, height: usize, stride: usize) -> Option<usize> {
    let row = width.checked_mul(SNAPIT_BYTES_PER_PIXEL)?;
    stride.checked_mul(height - 1)?.checked_add(row)
}

/// Copies the `width` x `height` pixels of an image that start at column `x`, row `y` into
/// `dst`, byte for byte: no resampling, no color conversion. The result's top-left pixel is the
/// source pixel at `(x, y)`.
///
/// Both images are BGRA, 8 bits per channel. Each is read or written through its own stride
/// (the distance in bytes between the starts of two rows, at least `width * 4`), so neither
/// has to be tight. Only the `width * 4` pixel bytes of each destination row are written; the
/// padding after them is left alone.
///
/// Returns `SNAPIT_STATUS_INVALID_ARGUMENT`, writing nothing, when a pointer is null, a size is
/// zero, a stride is too small, the rectangle is not wholly inside the source image, or the two
/// images overlap in memory.
///
/// # Safety
///
/// `src` must be valid for reads of `src_stride * (src_height - 1) + src_width * 4` bytes and
/// `dst` valid for writes of `dst_stride * (height - 1) + width * 4` bytes, for the whole call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_crop(
    src: *const u8,
    src_width: u32,
    src_height: u32,
    src_stride: usize,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    dst: *mut u8,
    dst_stride: usize,
) -> SnapitStatus {
    guard(|| {
        if src.is_null() || dst.is_null() || width == 0 || height == 0 {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // The rectangle must lie inside the source: checked in u64 so no sum can wrap.
        let (x, y, w, h) = (
            u64::from(x),
            u64::from(y),
            u64::from(width),
            u64::from(height),
        );
        if x + w > u64::from(src_width) || y + h > u64::from(src_height) {
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
        for r in 0..h as usize {
            // SAFETY: the caller guarantees both spans; row `r` of the rectangle lies inside
            // them, and the two spans do not overlap.
            unsafe {
                let from =
                    src.add((y as usize + r) * src_stride + x as usize * SNAPIT_BYTES_PER_PIXEL);
                ptr::copy_nonoverlapping(from, dst.add(r * dst_stride), row);
            }
        }
        SNAPIT_STATUS_OK
    })
}
