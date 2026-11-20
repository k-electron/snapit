//! Engine-owned pixel memory.
//!
//! A Capture's pixels live in anonymous `mmap` memory the engine hands to Swift. Freeing
//! it unmaps the pages, so the process footprint returns to where it was before the
//! Capture (a `malloc` block of that size would linger).

use std::ptr;

use crate::{
    SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, SNAPIT_STATUS_OUT_OF_MEMORY, SnapitStatus,
    guard,
};

/// Bytes per pixel: BGRA, 8 bits per channel, alpha in the top byte (premultiplied; Captures
/// are opaque).
pub const SNAPIT_BYTES_PER_PIXEL: usize = 4;

/// Rows start on this boundary, the alignment display buffers use.
pub const SNAPIT_ROW_ALIGNMENT: usize = 64;

/// A block of pixels owned by the engine: BGRA, 8 bits per channel, top row first.
///
/// `stride` is the distance in bytes between the starts of two rows and is at least
/// `width * 4`; the engine pads rows, so never assume it is tight. Every engine call that
/// reads pixels takes the stride.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SnapitPixelBuffer {
    /// First byte of the top row. Null when the buffer is not mapped.
    pub data: *mut u8,
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Bytes between the starts of two rows.
    pub stride: usize,
    /// Length of the mapping in bytes (whole pages).
    pub mapped_len: usize,
}

pub(crate) fn page_size() -> usize {
    // SAFETY: `sysconf` has no preconditions.
    let size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if size > 0 { size as usize } else { 16384 }
}

/// The row stride and mapped length (whole pages) of a `width` x `height` image, or `None`
/// when the size overflows or is larger than any display produces.
pub(crate) fn layout(width: u32, height: u32) -> Option<(usize, usize)> {
    let stride = (width as usize)
        .checked_mul(SNAPIT_BYTES_PER_PIXEL)?
        .checked_next_multiple_of(SNAPIT_ROW_ALIGNMENT)?;
    let mapped_len = stride
        .checked_mul(height as usize)?
        .checked_next_multiple_of(page_size())?;
    (mapped_len <= isize::MAX as usize / 2).then_some((stride, mapped_len))
}

/// Maps a zero-filled buffer for a `width` x `height` image and stores it in `out`.
///
/// The stride is chosen by the engine. Free the buffer with [`snapit_buffer_free`].
///
/// # Safety
///
/// `out` must be valid for a write of one `SnapitPixelBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_buffer_alloc(
    width: u32,
    height: u32,
    out: *mut SnapitPixelBuffer,
) -> SnapitStatus {
    guard(|| {
        if out.is_null() || width == 0 || height == 0 {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let Some((stride, mapped_len)) = layout(width, height) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        // SAFETY: an anonymous private mapping has no preconditions on its arguments.
        let data = unsafe {
            libc::mmap(
                ptr::null_mut(),
                mapped_len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_PRIVATE | libc::MAP_ANON,
                -1,
                0,
            )
        };
        if data == libc::MAP_FAILED {
            return SNAPIT_STATUS_OUT_OF_MEMORY;
        }
        // SAFETY: the caller guarantees `out` is writable.
        unsafe {
            out.write(SnapitPixelBuffer {
                data: data.cast(),
                width,
                height,
                stride,
                mapped_len,
            });
        }
        SNAPIT_STATUS_OK
    })
}

/// Unmaps a buffer from [`snapit_buffer_alloc`] and clears it. Freeing an already freed
/// buffer does nothing.
///
/// # Safety
///
/// `buffer` must point to a `SnapitPixelBuffer` the engine filled in (or one already freed),
/// and nothing may use its pixels afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_buffer_free(buffer: *mut SnapitPixelBuffer) -> SnapitStatus {
    guard(|| {
        if buffer.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // SAFETY: the caller guarantees `buffer` points to a buffer the engine filled in.
        let b = unsafe { &mut *buffer };
        if !b.data.is_null() {
            // SAFETY: `data` and `mapped_len` describe a mapping `snapit_buffer_alloc` made.
            unsafe { libc::munmap(b.data.cast(), b.mapped_len) };
        }
        *b = SnapitPixelBuffer {
            data: ptr::null_mut(),
            width: 0,
            height: 0,
            stride: 0,
            mapped_len: 0,
        };
        SNAPIT_STATUS_OK
    })
}
