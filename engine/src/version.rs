use std::ffi::c_char;
use std::ptr;

use crate::{
    SNAPIT_STATUS_BUFFER_TOO_SMALL, SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, SnapitStatus,
    guard,
};

fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Copies the engine version, NUL terminated, into `buffer` (capacity `capacity` bytes)
/// and stores its length without the NUL in `out_length`.
///
/// If the buffer is too small nothing is written, `out_length` receives the length
/// needed without the NUL, and the status is `SNAPIT_STATUS_BUFFER_TOO_SMALL`.
///
/// # Safety
///
/// `buffer` must be valid for writes of `capacity` bytes and `out_length` must be valid
/// for a write of one `usize`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_engine_version(
    buffer: *mut c_char,
    capacity: usize,
    out_length: *mut usize,
) -> SnapitStatus {
    guard(|| {
        if buffer.is_null() || out_length.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let bytes = version().as_bytes();
        // SAFETY: the caller guarantees `out_length` is writable.
        unsafe { out_length.write(bytes.len()) };
        if capacity < bytes.len() + 1 {
            return SNAPIT_STATUS_BUFFER_TOO_SMALL;
        }
        // SAFETY: the caller guarantees `buffer` holds `capacity` bytes, and
        // `bytes.len() + 1 <= capacity`.
        unsafe {
            ptr::copy_nonoverlapping(bytes.as_ptr(), buffer.cast::<u8>(), bytes.len());
            buffer.cast::<u8>().add(bytes.len()).write(0);
        }
        SNAPIT_STATUS_OK
    })
}
