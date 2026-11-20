//! snapit's image engine. Swift calls it through the C ABI declared in
//! `include/snapit_engine.h`, which cbindgen generates from this crate.
//!
//! Every entry point runs inside [`guard`], so a panic never unwinds into Swift: it
//! comes back as [`SNAPIT_STATUS_PANIC`].

mod buffer;
mod capture_file;
mod crop;
mod pixelate;
mod png_encode;
mod version;

use std::panic::{AssertUnwindSafe, catch_unwind};

pub use buffer::{
    SNAPIT_BYTES_PER_PIXEL, SNAPIT_ROW_ALIGNMENT, SnapitPixelBuffer, snapit_buffer_alloc,
    snapit_buffer_free,
};
pub use capture_file::{
    SNAPIT_PIXEL_FORMAT_BGRA8_PREMULTIPLIED, SnapitCaptureHeader, snapit_capture_file_create,
    snapit_capture_file_icc, snapit_capture_file_info, snapit_capture_file_map,
};
pub use crop::snapit_crop;
pub use pixelate::snapit_pixelate;
pub use png_encode::{
    SNAPIT_PNG_BALANCED, SNAPIT_PNG_FAST, SNAPIT_PNG_HIGH, SnapitBytes, snapit_bytes_free,
    snapit_png_encode,
};
pub use version::snapit_engine_version;

/// Result of every engine entry point: one of the `SNAPIT_STATUS_*` values.
///
/// A plain integer rather than a C enum, so the header means the same thing to every C
/// standard and Swift toolchain.
pub type SnapitStatus = i32;

/// The call succeeded.
pub const SNAPIT_STATUS_OK: SnapitStatus = 0;
/// A pointer was null or a size was out of range.
pub const SNAPIT_STATUS_INVALID_ARGUMENT: SnapitStatus = 1;
/// The output buffer is too small; the needed length is reported separately.
pub const SNAPIT_STATUS_BUFFER_TOO_SMALL: SnapitStatus = 2;
/// The engine panicked. The call had no effect.
pub const SNAPIT_STATUS_PANIC: SnapitStatus = 3;
/// The system had no memory to map.
pub const SNAPIT_STATUS_OUT_OF_MEMORY: SnapitStatus = 4;
/// The PNG encoder failed.
pub const SNAPIT_STATUS_ENCODE_FAILED: SnapitStatus = 5;
/// A file operation failed (the disk is full, the file could not be written).
pub const SNAPIT_STATUS_IO_FAILED: SnapitStatus = 6;
/// A Capture file is damaged, truncated or from another version.
pub const SNAPIT_STATUS_INVALID_FILE: SnapitStatus = 7;

/// Runs `body`, turning a panic into [`SNAPIT_STATUS_PANIC`].
pub(crate) fn guard(body: impl FnOnce() -> SnapitStatus) -> SnapitStatus {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(SNAPIT_STATUS_PANIC)
}

/// Deliberately panics inside the guard. The scripted run and the Cargo tests use it to
/// prove a panic reaches Swift as a status code.
#[unsafe(no_mangle)]
pub extern "C" fn snapit_engine_probe_panic() -> SnapitStatus {
    guard(|| panic!("snapit_engine_probe_panic"))
}
