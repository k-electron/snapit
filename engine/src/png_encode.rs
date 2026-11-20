//! PNG encoding of BGRA pixels, with the physical size and color profile a Capture carries.

use std::borrow::Cow;
use std::io::Write;
use std::ptr;
use std::slice;

use png::{BitDepth, ColorType, Compression, Info, PixelDimensions, Unit};

use crate::buffer::SNAPIT_BYTES_PER_PIXEL;
use crate::{
    SNAPIT_STATUS_ENCODE_FAILED, SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK,
    SNAPIT_STATUS_OUT_OF_MEMORY, SnapitStatus, guard,
};

/// Fast: the encoder Copy and drag-out use.
pub const SNAPIT_PNG_FAST: u32 = 0;
/// Balanced: the encoder Save uses.
pub const SNAPIT_PNG_BALANCED: u32 = 1;
/// High: smallest file, slowest.
pub const SNAPIT_PNG_HIGH: u32 = 2;

/// Bytes the engine allocated and hands to the caller. Free with [`snapit_bytes_free`].
#[repr(C)]
pub struct SnapitBytes {
    /// First byte. Null when empty.
    pub data: *mut u8,
    /// Number of bytes in use.
    pub len: usize,
    /// Number of bytes allocated.
    pub capacity: usize,
}

/// PNG pixels per metre for a resolution in dots per inch.
fn pixels_per_metre(dpi: u32) -> u32 {
    (f64::from(dpi) / 0.0254).round() as u32
}

enum EncodeError {
    OutOfMemory,
    Failed,
}

impl From<png::EncodingError> for EncodeError {
    fn from(_: png::EncodingError) -> Self {
        Self::Failed
    }
}

impl From<std::io::Error> for EncodeError {
    fn from(_: std::io::Error) -> Self {
        Self::Failed
    }
}

fn encode(
    pixels: &[u8],
    width: u32,
    height: u32,
    stride: usize,
    level: u32,
    dpi: u32,
    icc: &[u8],
) -> Result<Vec<u8>, EncodeError> {
    let (w, h) = (width as usize, height as usize);
    let mut info = Info::with_size(width, height);
    info.color_type = ColorType::Rgb;
    info.bit_depth = BitDepth::Eight;
    let ppm = pixels_per_metre(dpi);
    info.pixel_dims = Some(PixelDimensions {
        xppu: ppm,
        yppu: ppm,
        unit: Unit::Meter,
    });
    if !icc.is_empty() {
        info.icc_profile = Some(Cow::Borrowed(icc));
    }

    // A Capture compresses to roughly a tenth of its size; start there and let it grow.
    let mut out: Vec<u8> = Vec::new();
    // Reserve up front at most 256 MiB; the output grows past that on demand.
    const MAX_INITIAL_RESERVE: usize = 256 << 20;
    let estimate = (w.saturating_mul(h) / 2 + 1024).min(MAX_INITIAL_RESERVE);
    out.try_reserve_exact(estimate)
        .map_err(|_| EncodeError::OutOfMemory)?;
    let mut encoder = png::Encoder::with_info(&mut out, info)?;
    encoder.set_compression(match level {
        SNAPIT_PNG_FAST => Compression::Fast,
        SNAPIT_PNG_HIGH => Compression::High,
        _ => Compression::Balanced,
    });
    let mut writer = encoder.write_header()?;
    {
        let mut stream = writer.stream_writer()?;
        let mut row = vec![[0u8; 3]; w];
        for y in 0..h {
            let source = &pixels[y * stride..y * stride + w * SNAPIT_BYTES_PER_PIXEL];
            let (source, _) = source.as_chunks::<SNAPIT_BYTES_PER_PIXEL>();
            for (dst, src) in row.iter_mut().zip(source) {
                *dst = [src[2], src[1], src[0]];
            }
            stream.write_all(row.as_flattened())?;
        }
        stream.finish()?;
    }
    writer.finish()?;
    Ok(out)
}

/// Encodes BGRA pixels as an RGB PNG (alpha is dropped) and stores the bytes in `out`.
///
/// * `stride` is the distance in bytes between rows and must be at least `width * 4`; bytes
///   between the end of a row and the start of the next are never read into the image.
/// * `level` is one of `SNAPIT_PNG_FAST`, `SNAPIT_PNG_BALANCED` or `SNAPIT_PNG_HIGH`.
/// * `dpi` becomes the `pHYs` chunk: 144 for a Retina Capture, 72 at 1x.
/// * `icc` and `icc_len` give the display's color profile, embedded as an `iCCP` chunk. Pass
///   null and 0 for none.
///
/// Free `out` with [`snapit_bytes_free`]. A refused call leaves `out` untouched.
///
/// # Safety
///
/// `pixels` must be valid for reads of `(height - 1) * stride + width * 4` bytes, `icc` for
/// `icc_len` bytes (when not null), and `out` for a write of one `SnapitBytes`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_png_encode(
    pixels: *const u8,
    width: u32,
    height: u32,
    stride: usize,
    level: u32,
    dpi: u32,
    icc: *const u8,
    icc_len: usize,
    out: *mut SnapitBytes,
) -> SnapitStatus {
    guard(|| {
        if pixels.is_null()
            || out.is_null()
            || width == 0
            || height == 0
            || dpi == 0
            || level > SNAPIT_PNG_HIGH
            || (icc.is_null() != (icc_len == 0))
        {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let row = width as usize * SNAPIT_BYTES_PER_PIXEL;
        let readable = (height as usize - 1)
            .checked_mul(stride)
            .and_then(|above_last_row| above_last_row.checked_add(row));
        let Some(readable) = readable.filter(|&len| stride >= row && len <= isize::MAX as usize)
        else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        // SAFETY: the caller guarantees `pixels` is readable for `readable` bytes.
        let pixels = unsafe { slice::from_raw_parts(pixels, readable) };
        let icc = if icc.is_null() {
            &[][..]
        } else {
            // SAFETY: the caller guarantees `icc` is readable for `icc_len` bytes.
            unsafe { slice::from_raw_parts(icc, icc_len) }
        };

        match encode(pixels, width, height, stride, level, dpi, icc) {
            Ok(png) => {
                let mut png = std::mem::ManuallyDrop::new(png);
                // SAFETY: the caller guarantees `out` is writable.
                unsafe {
                    out.write(SnapitBytes {
                        data: png.as_mut_ptr(),
                        len: png.len(),
                        capacity: png.capacity(),
                    });
                }
                SNAPIT_STATUS_OK
            }
            Err(EncodeError::OutOfMemory) => SNAPIT_STATUS_OUT_OF_MEMORY,
            Err(EncodeError::Failed) => SNAPIT_STATUS_ENCODE_FAILED,
        }
    })
}

/// Releases bytes from [`snapit_png_encode`] and clears them. Freeing empty bytes does nothing.
///
/// # Safety
///
/// `bytes` must point to a `SnapitBytes` the engine filled in (or an empty one).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_bytes_free(bytes: *mut SnapitBytes) -> SnapitStatus {
    guard(|| {
        if bytes.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // SAFETY: the caller guarantees `bytes` points to a `SnapitBytes`.
        let b = unsafe { &mut *bytes };
        if !b.data.is_null() {
            // SAFETY: `data`, `len` and `capacity` came from a `Vec<u8>` leaked by the encoder.
            drop(unsafe { Vec::from_raw_parts(b.data, b.len, b.capacity) });
        }
        b.data = ptr::null_mut();
        b.len = 0;
        b.capacity = 0;
        SNAPIT_STATUS_OK
    })
}
