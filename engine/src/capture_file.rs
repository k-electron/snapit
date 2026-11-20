//! The Capture file: how a Capture's pixels move between snapit's two processes.
//!
//! The menu bar app creates the file and draws the Capture into its mapping; the Editor
//! helper maps the same file read-only. The pixels never travel over a socket, and no
//! encode or decode happens at Capture time or on Reopen. Layout, in this order:
//!
//! 1. a [`SnapitCaptureHeader`] at offset 0,
//! 2. the display's ICC profile, right after the header (`icc_offset`, `icc_len`),
//! 3. the pixels at `pixel_offset`, a page boundary, `stride * height` bytes, in the layout
//!    of [`SnapitPixelBuffer`](crate::SnapitPixelBuffer).
//!
//! The file is little-endian, as the machines snapit runs on are.

use std::mem::size_of;
use std::ptr;
use std::slice;

use crate::buffer::{layout, page_size};
use crate::{
    SNAPIT_BYTES_PER_PIXEL, SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_INVALID_FILE,
    SNAPIT_STATUS_IO_FAILED, SNAPIT_STATUS_OK, SNAPIT_STATUS_OUT_OF_MEMORY, SnapitPixelBuffer,
    SnapitStatus, guard,
};

/// BGRA, 8 bits per channel, alpha in the top byte, premultiplied, top row first.
pub const SNAPIT_PIXEL_FORMAT_BGRA8_PREMULTIPLIED: u32 = 1;

const MAGIC: [u8; 8] = *b"SNAPCAP\0";
const VERSION: u32 = 1;
const HEADER_SIZE: u64 = size_of::<SnapitCaptureHeader>() as u64;

// The header is part of the file format: any change to its layout is a new version.
const _: () = assert!(size_of::<SnapitCaptureHeader>() == 72);

/// The fixed-size start of a Capture file.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SnapitCaptureHeader {
    /// Identifies the file; always `SNAPCAP` and a NUL.
    pub magic: [u8; 8],
    /// Format version; 1.
    pub version: u32,
    /// One of the `SNAPIT_PIXEL_FORMAT_*` values.
    pub pixel_format: u32,
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Bytes between the starts of two rows.
    pub stride: u64,
    /// Pixels per point: 2 on a Retina display, 1 otherwise.
    pub scale: f64,
    /// When the Capture was taken, in seconds since 1970.
    pub capture_time: i64,
    /// Where the pixels start in the file: a page boundary.
    pub pixel_offset: u64,
    /// Where the ICC profile starts in the file.
    pub icc_offset: u64,
    /// Length of the ICC profile in bytes; 0 for none.
    pub icc_len: u64,
}

fn file_len(fd: i32) -> Option<u64> {
    // SAFETY: `stat` is plain data and `fstat` only writes into it.
    let mut stat: libc::stat = unsafe { std::mem::zeroed() };
    // SAFETY: `stat` is a valid destination.
    (unsafe { libc::fstat(fd, &mut stat) } == 0).then_some(stat.st_size as u64)
}

/// True when the last system call was interrupted by a signal and should be retried.
fn interrupted() -> bool {
    std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted
}

fn write_all_at(fd: i32, mut bytes: &[u8], mut offset: u64) -> bool {
    while !bytes.is_empty() {
        // SAFETY: `bytes` is a valid slice.
        let n = unsafe { libc::pwrite(fd, bytes.as_ptr().cast(), bytes.len(), offset as i64) };
        if n < 0 && interrupted() {
            continue;
        }
        if n <= 0 {
            return false;
        }
        bytes = &bytes[n as usize..];
        offset += n as u64;
    }
    true
}

fn read_exact_at(fd: i32, mut bytes: &mut [u8], mut offset: u64) -> bool {
    while !bytes.is_empty() {
        // SAFETY: `bytes` is a valid slice.
        let n = unsafe { libc::pread(fd, bytes.as_mut_ptr().cast(), bytes.len(), offset as i64) };
        if n < 0 && interrupted() {
            continue;
        }
        if n <= 0 {
            return false;
        }
        let rest = bytes;
        bytes = &mut rest[n as usize..];
        offset += n as u64;
    }
    true
}

/// True when `header` describes a Capture file of `len` bytes that holds all its pixels.
fn describes_file(header: &SnapitCaptureHeader, len: u64) -> bool {
    let row = u64::from(header.width).checked_mul(SNAPIT_BYTES_PER_PIXEL as u64);
    let pixels = header.stride.checked_mul(u64::from(header.height));
    let (Some(row), Some(pixels)) = (row, pixels) else {
        return false;
    };
    let pixel_end = header.pixel_offset.checked_add(pixels);
    let icc_end = header.icc_offset.checked_add(header.icc_len);
    header.magic == MAGIC
        && header.version == VERSION
        && header.pixel_format == SNAPIT_PIXEL_FORMAT_BGRA8_PREMULTIPLIED
        && header.width > 0
        && header.height > 0
        && header.stride >= row
        && header.stride.is_multiple_of(SNAPIT_BYTES_PER_PIXEL as u64)
        && header.scale.is_finite()
        && header.scale > 0.0
        && header.icc_offset == HEADER_SIZE
        && icc_end.is_some_and(|end| end <= header.pixel_offset)
        && header.pixel_offset.is_multiple_of(page_size() as u64)
        && pixel_end.is_some_and(|end| end <= len)
}

/// Fills `file` with a Capture file for a `width` x `height` image and maps its pixels
/// writable (shared, so the helper sees what is written) into `out_buffer`.
///
/// The file is sized, then given its header and ICC profile; the stride is chosen by the
/// engine and returned in `out_header`. `scale` is pixels per point, `capture_time` seconds
/// since 1970. `icc` and `icc_len` give the display's color profile (null and 0 for none).
/// Free the mapping with `snapit_buffer_free`.
///
/// # Safety
///
/// `fd` must be a file open for reading and writing, `icc` valid for `icc_len` bytes (when
/// not null), `out_header` and `out_buffer` valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_capture_file_create(
    fd: i32,
    width: u32,
    height: u32,
    scale: f64,
    capture_time: i64,
    icc: *const u8,
    icc_len: usize,
    out_header: *mut SnapitCaptureHeader,
    out_buffer: *mut SnapitPixelBuffer,
) -> SnapitStatus {
    guard(|| {
        if fd < 0
            || out_header.is_null()
            || out_buffer.is_null()
            || width == 0
            || height == 0
            || !scale.is_finite()
            || scale <= 0.0
            || (icc.is_null() && icc_len != 0)
        {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let Some((stride, mapped_len)) = layout(width, height) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        let page = page_size() as u64;
        let Some(pixel_offset) = HEADER_SIZE
            .checked_add(icc_len as u64)
            .and_then(|end| end.checked_next_multiple_of(page))
        else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        let Some(total) = pixel_offset.checked_add(mapped_len as u64) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };

        let header = SnapitCaptureHeader {
            magic: MAGIC,
            version: VERSION,
            pixel_format: SNAPIT_PIXEL_FORMAT_BGRA8_PREMULTIPLIED,
            width,
            height,
            stride: stride as u64,
            scale,
            capture_time,
            pixel_offset,
            icc_offset: HEADER_SIZE,
            icc_len: icc_len as u64,
        };
        // SAFETY: `header` is `repr(C)` plain data without padding.
        let header_bytes = unsafe {
            slice::from_raw_parts(
                ptr::from_ref(&header).cast::<u8>(),
                size_of::<SnapitCaptureHeader>(),
            )
        };

        // SAFETY: `fd` is a file descriptor the caller owns.
        if unsafe { libc::ftruncate(fd, total as i64) } != 0 {
            return SNAPIT_STATUS_IO_FAILED;
        }
        if !write_all_at(fd, header_bytes, 0) {
            return SNAPIT_STATUS_IO_FAILED;
        }
        if icc_len > 0 {
            // SAFETY: the caller guarantees `icc` is valid for `icc_len` bytes.
            let profile = unsafe { slice::from_raw_parts(icc, icc_len) };
            if !write_all_at(fd, profile, HEADER_SIZE) {
                return SNAPIT_STATUS_IO_FAILED;
            }
        }
        let status = map(fd, &header, true, out_buffer);
        if status == SNAPIT_STATUS_OK {
            // SAFETY: the caller guarantees `out_header` is writable.
            unsafe { out_header.write(header) };
        }
        status
    })
}

/// Reads and checks the header of the Capture file `fd` and stores it in `out_header`.
///
/// Refuses (with `SNAPIT_STATUS_INVALID_FILE`) a file that is empty, truncated, has the
/// wrong magic or version, or does not hold all the pixels its header describes, so mapping
/// it can never read past its end.
///
/// # Safety
///
/// `fd` must be a file open for reading and `out_header` valid for a write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_capture_file_info(
    fd: i32,
    out_header: *mut SnapitCaptureHeader,
) -> SnapitStatus {
    guard(|| {
        if fd < 0 || out_header.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let Some(len) = file_len(fd) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        let mut raw = [0u8; size_of::<SnapitCaptureHeader>()];
        if !read_exact_at(fd, &mut raw, 0) {
            return SNAPIT_STATUS_INVALID_FILE;
        }
        // SAFETY: every bit pattern is a valid `SnapitCaptureHeader` (integers, a float and
        // bytes); `describes_file` checks the values before they are used.
        let header: SnapitCaptureHeader = unsafe { ptr::read_unaligned(raw.as_ptr().cast()) };
        if !describes_file(&header, len) {
            return SNAPIT_STATUS_INVALID_FILE;
        }
        // SAFETY: the caller guarantees `out_header` is writable.
        unsafe { out_header.write(header) };
        SNAPIT_STATUS_OK
    })
}

/// Copies the ICC profile of the Capture file `fd` (`header.icc_len` bytes) into `buffer`,
/// which holds `capacity` bytes. With no profile it copies nothing. When `capacity` is too
/// small nothing is copied and the status is `SNAPIT_STATUS_BUFFER_TOO_SMALL`.
///
/// # Safety
///
/// `fd` must be a file open for reading, `header` the header `snapit_capture_file_info`
/// returned for it, `buffer` valid for writes of `capacity` bytes (it may be null when the
/// header has no profile).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_capture_file_icc(
    fd: i32,
    header: *const SnapitCaptureHeader,
    buffer: *mut u8,
    capacity: usize,
) -> SnapitStatus {
    guard(|| {
        if fd < 0 || header.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // SAFETY: the caller guarantees `header` is valid.
        let header = unsafe { *header };
        let Some(len) = file_len(fd) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        if !describes_file(&header, len) {
            return SNAPIT_STATUS_INVALID_FILE;
        }
        let wanted = header.icc_len as usize;
        if wanted == 0 {
            return SNAPIT_STATUS_OK;
        }
        if buffer.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        if capacity < wanted {
            return crate::SNAPIT_STATUS_BUFFER_TOO_SMALL;
        }
        // SAFETY: the caller guarantees `buffer` is valid for `capacity >= wanted` bytes.
        let destination = unsafe { slice::from_raw_parts_mut(buffer, wanted) };
        if read_exact_at(fd, destination, header.icc_offset) {
            SNAPIT_STATUS_OK
        } else {
            SNAPIT_STATUS_IO_FAILED
        }
    })
}

/// Maps the pixels of the Capture file `fd`, described by `header`, into `out`. `writable`
/// 0 maps them read-only (the Editor helper), anything else writable (the menu bar app). The
/// mapping is shared: free it with `snapit_buffer_free`, which
/// unmaps it and returns the memory to the OS.
///
/// Refuses a `header` the file does not back (`SNAPIT_STATUS_INVALID_FILE`).
///
/// # Safety
///
/// `fd` must be a file open for reading (and writing when `writable` is not 0), `header`
/// valid for a read, `out` valid for a write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_capture_file_map(
    fd: i32,
    header: *const SnapitCaptureHeader,
    writable: u32,
    out: *mut SnapitPixelBuffer,
) -> SnapitStatus {
    guard(|| {
        if fd < 0 || header.is_null() || out.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // SAFETY: the caller guarantees `header` is valid.
        let header = unsafe { *header };
        let Some(len) = file_len(fd) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        if !describes_file(&header, len) {
            return SNAPIT_STATUS_INVALID_FILE;
        }
        map(fd, &header, writable != 0, out)
    })
}

fn map(
    fd: i32,
    header: &SnapitCaptureHeader,
    writable: bool,
    out: *mut SnapitPixelBuffer,
) -> SnapitStatus {
    let Some(mapped_len) = usize::try_from(header.stride)
        .ok()
        .and_then(|stride| stride.checked_mul(header.height as usize))
        .and_then(|len| len.checked_next_multiple_of(page_size()))
    else {
        return SNAPIT_STATUS_INVALID_ARGUMENT;
    };
    let protection = if writable {
        libc::PROT_READ | libc::PROT_WRITE
    } else {
        libc::PROT_READ
    };
    // SAFETY: a shared file mapping of a descriptor the caller owns; the file was checked to
    // hold `pixel_offset + stride * height` bytes.
    let data = unsafe {
        libc::mmap(
            ptr::null_mut(),
            mapped_len,
            protection,
            libc::MAP_SHARED,
            fd,
            header.pixel_offset as i64,
        )
    };
    if data == libc::MAP_FAILED {
        return if writable {
            SNAPIT_STATUS_IO_FAILED
        } else {
            SNAPIT_STATUS_OUT_OF_MEMORY
        };
    }
    // SAFETY: the caller guarantees `out` is writable.
    unsafe {
        out.write(SnapitPixelBuffer {
            data: data.cast(),
            width: header.width,
            height: header.height,
            stride: header.stride as usize,
            mapped_len,
        });
    }
    SNAPIT_STATUS_OK
}
