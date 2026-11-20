//! PNG encoding of BGRA pixels, with the physical size and color profile a Capture carries.
//!
//! The pixels are premultiplied BGRA. An image whose every pixel is opaque (every Capture of a
//! screen) becomes an RGB PNG. An image with any transparent or translucent pixel (a Window
//! Capture's rounded corners) becomes an RGBA PNG whose colours are un-premultiplied, as PNG
//! stores them. The engine looks at the pixels to decide, so the decision survives the Capture
//! file, the Export pipeline and a Save that is encoded in another process.
//!
//! Three entry points share one encoder: [`snapit_png_encode`] (the original, bytes out),
//! [`snapit_png_encode_ex`] (bytes out, with the 1x downscale) and [`snapit_png_encode_to_fd`]
//! (streamed into a file, for Save and drag-out). The downscale is made in the same pass as the
//! encode, one row at a time: no buffer of the smaller image exists. Output bytes live in
//! page-backed memory that [`snapit_bytes_free`] unmaps, so the footprint returns to where it
//! was; a file is written through a buffer of a few hundred kilobytes.

use std::borrow::Cow;
use std::fs::File;
use std::io::{self, BufWriter, Write};
use std::mem::ManuallyDrop;
use std::os::fd::FromRawFd;
use std::ptr;
use std::slice;

use png::{BitDepth, ColorType, Compression, Info, PixelDimensions, Unit};

use crate::buffer::{SNAPIT_BYTES_PER_PIXEL, page_size};
use crate::downscale::{Downscaler, Source, readable_len, valid_target, within_averaging_limit};
use crate::{
    SNAPIT_STATUS_ENCODE_FAILED, SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_IO_FAILED,
    SNAPIT_STATUS_OK, SNAPIT_STATUS_OUT_OF_MEMORY, SnapitStatus, guard,
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
    /// Length of the page-backed allocation in bytes (whole pages).
    pub capacity: usize,
}

/// How to encode: the level, the resolution to record, the size of the PNG and the color profile.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SnapitPngParams {
    /// One of `SNAPIT_PNG_FAST`, `SNAPIT_PNG_BALANCED` or `SNAPIT_PNG_HIGH`.
    pub level: u32,
    /// Becomes the `pHYs` chunk: 144 for a Retina Capture, 72 at 1x.
    pub dpi: u32,
    /// Width of the PNG in pixels: the source width, or less to average the image down to it.
    pub out_width: u32,
    /// Height of the PNG in pixels: the source height, or less.
    pub out_height: u32,
    /// The display's color profile, embedded as an `iCCP` chunk; null (with `icc_len` 0) for none.
    pub icc: *const u8,
    /// Length of `icc` in bytes.
    pub icc_len: usize,
}

/// PNG pixels per metre for a resolution in dots per inch.
fn pixels_per_metre(dpi: u32) -> u32 {
    (f64::from(dpi) / 0.0254).round() as u32
}

enum EncodeError {
    OutOfMemory,
    Io,
    Failed,
}

impl From<png::EncodingError> for EncodeError {
    fn from(error: png::EncodingError) -> Self {
        match error {
            png::EncodingError::IoError(e) if e.kind() == io::ErrorKind::OutOfMemory => {
                Self::OutOfMemory
            }
            png::EncodingError::IoError(_) => Self::Io,
            _ => Self::Failed,
        }
    }
}

impl From<io::Error> for EncodeError {
    fn from(error: io::Error) -> Self {
        if error.kind() == io::ErrorKind::OutOfMemory {
            Self::OutOfMemory
        } else {
            Self::Io
        }
    }
}

/// True when some pixel of `source` has an alpha below 255. Reads only the pixels of each row,
/// never the padding, and stops at the first row that has one.
fn has_transparency(source: &Source) -> bool {
    (0..source.height).any(|y| {
        let row = &source.pixels[y * source.stride..][..source.width * SNAPIT_BYTES_PER_PIXEL];
        // AND of every pixel as one word: the alpha byte stays 0xFF only if every alpha is.
        let (words, _) = row.as_chunks::<SNAPIT_BYTES_PER_PIXEL>();
        words
            .iter()
            .fold(u32::MAX, |all, w| all & u32::from_le_bytes(*w))
            >> 24
            != 0xFF
    })
}

/// A premultiplied channel as the PNG stores it: divided by alpha (rounded), clamped to 255.
fn straight(channel: u8, alpha: u8) -> u8 {
    match alpha {
        255 => channel,
        0 => 0,
        _ => ((u32::from(channel) * 255 + u32::from(alpha) / 2) / u32::from(alpha)).min(255) as u8,
    }
}

/// Premultiplied BGRA pixels as RGB (opaque pixels: alpha is 255 and nothing changes).
fn bgra_to_rgb(bgra: &[u8], rgb: &mut [u8]) {
    let (out, _) = rgb.as_chunks_mut::<3>();
    let (pixels, _) = bgra.as_chunks::<SNAPIT_BYTES_PER_PIXEL>();
    for (dst, src) in out.iter_mut().zip(pixels) {
        *dst = [src[2], src[1], src[0]];
    }
}

/// Premultiplied BGRA pixels as straight RGBA.
fn bgra_to_rgba(bgra: &[u8], rgba: &mut [u8]) {
    let (out, _) = rgba.as_chunks_mut::<4>();
    let (pixels, _) = bgra.as_chunks::<SNAPIT_BYTES_PER_PIXEL>();
    for (dst, src) in out.iter_mut().zip(pixels) {
        let a = src[3];
        *dst = [
            straight(src[2], a),
            straight(src[1], a),
            straight(src[0], a),
            a,
        ];
    }
}

impl Job<'_> {
    /// Bytes per pixel of the PNG: 4 with alpha, 3 without.
    fn channels(&self) -> usize {
        if self.has_alpha { 4 } else { 3 }
    }
}

impl EncodeError {
    fn status(&self) -> SnapitStatus {
        match self {
            Self::OutOfMemory => SNAPIT_STATUS_OUT_OF_MEMORY,
            Self::Io => SNAPIT_STATUS_IO_FAILED,
            Self::Failed => SNAPIT_STATUS_ENCODE_FAILED,
        }
    }
}

/// A validated call: the source pixels and how to encode them.
struct Job<'a> {
    source: Source<'a>,
    /// Some pixel of the source is not opaque: the PNG carries an alpha channel.
    has_alpha: bool,
    level: u32,
    dpi: u32,
    out_width: usize,
    out_height: usize,
    icc: &'a [u8],
}

/// Encodes `job` into `sink`: the PNG, row by row, averaging rows down when the output is
/// smaller than the source.
fn encode_into<W: Write>(sink: W, job: &Job) -> Result<(), EncodeError> {
    let Job {
        source,
        out_width: w,
        out_height: h,
        ..
    } = *job;
    let mut info = Info::with_size(w as u32, h as u32);
    let channels = job.channels();
    info.color_type = if job.has_alpha {
        ColorType::Rgba
    } else {
        ColorType::Rgb
    };
    info.bit_depth = BitDepth::Eight;
    let ppm = pixels_per_metre(job.dpi);
    info.pixel_dims = Some(PixelDimensions {
        xppu: ppm,
        yppu: ppm,
        unit: Unit::Meter,
    });
    if !job.icc.is_empty() {
        info.icc_profile = Some(Cow::Borrowed(job.icc));
    }

    let mut encoder = png::Encoder::with_info(sink, info)?;
    encoder.set_compression(match job.level {
        SNAPIT_PNG_FAST => Compression::Fast,
        SNAPIT_PNG_HIGH => Compression::High,
        _ => Compression::Balanced,
    });
    let mut writer = encoder.write_header()?;
    {
        let mut stream = writer.stream_writer()?;
        let mut row = vec![0u8; w * channels];
        let convert = if job.has_alpha {
            bgra_to_rgba
        } else {
            bgra_to_rgb
        };
        if (w, h) == (source.width, source.height) {
            for y in 0..h {
                let pixels = &source.pixels[y * source.stride..][..w * SNAPIT_BYTES_PER_PIXEL];
                convert(pixels, &mut row);
                stream.write_all(&row)?;
            }
        } else {
            let mut scaler = Downscaler::new(source, w, h);
            let mut averaged = vec![0u8; w * SNAPIT_BYTES_PER_PIXEL];
            for y in 0..h {
                scaler.row_bgra(y, &mut averaged);
                convert(&averaged, &mut row);
                stream.write_all(&row)?;
            }
        }
        stream.finish()?;
    }
    writer.finish()?;
    Ok(())
}

/// Checks a call's arguments and builds its [`Job`], or says which status to return.
///
/// # Safety
///
/// `pixels` must be valid for reads of `(height - 1) * stride + width * 4` bytes (when the sizes
/// pass), and the profile in `params` for `icc_len` bytes.
unsafe fn make_job<'a>(
    pixels: *const u8,
    width: u32,
    height: u32,
    stride: usize,
    params: *const SnapitPngParams,
) -> Result<Job<'a>, SnapitStatus> {
    if pixels.is_null() || params.is_null() || width == 0 || height == 0 {
        return Err(SNAPIT_STATUS_INVALID_ARGUMENT);
    }
    // SAFETY: the caller guarantees `params` is readable.
    let p = unsafe { *params };
    let scaled = (p.out_width, p.out_height) != (width, height);
    if p.dpi == 0
        || p.level > SNAPIT_PNG_HIGH
        || p.icc.is_null() != (p.icc_len == 0)
        || !valid_target(width, height, p.out_width, p.out_height)
        || (scaled && !within_averaging_limit(width, height))
    {
        return Err(SNAPIT_STATUS_INVALID_ARGUMENT);
    }
    let Some(readable) = readable_len(width, height, stride) else {
        return Err(SNAPIT_STATUS_INVALID_ARGUMENT);
    };
    // SAFETY: the caller guarantees `pixels` is readable for `readable` bytes.
    let pixels = unsafe { slice::from_raw_parts(pixels, readable) };
    let icc = if p.icc.is_null() {
        &[][..]
    } else {
        // SAFETY: the caller guarantees `icc` is readable for `icc_len` bytes.
        unsafe { slice::from_raw_parts(p.icc, p.icc_len) }
    };
    let source = Source {
        pixels,
        width: width as usize,
        height: height as usize,
        stride,
    };
    Ok(Job {
        has_alpha: has_transparency(&source),
        source,
        level: p.level,
        dpi: p.dpi,
        out_width: p.out_width as usize,
        out_height: p.out_height as usize,
        icc,
    })
}

/// A write-only sink into one anonymous `mmap` allocation sized to the largest PNG the image
/// can make. Pages that are never written cost nothing, and unmapping returns them all.
struct MappedSink {
    data: *mut u8,
    len: usize,
    capacity: usize,
}

impl MappedSink {
    fn new(job: &Job) -> Result<Self, EncodeError> {
        // Raw rows (RGB or RGBA) with a filter byte each, plus generous room for compression
        // framing, chunk headers and the profile.
        let raw = job
            .out_height
            .checked_mul(job.out_width * job.channels() + 1)
            .ok_or(EncodeError::OutOfMemory)?;
        let bound = raw
            .checked_add(raw / 8 + job.icc.len() + 64 * 1024)
            .and_then(|n| n.checked_next_multiple_of(page_size()))
            .filter(|&n| n <= isize::MAX as usize / 2)
            .ok_or(EncodeError::OutOfMemory)?;
        // SAFETY: an anonymous private mapping has no preconditions on its arguments.
        let data = unsafe {
            libc::mmap(
                ptr::null_mut(),
                bound,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_PRIVATE | libc::MAP_ANON,
                -1,
                0,
            )
        };
        if data == libc::MAP_FAILED {
            return Err(EncodeError::OutOfMemory);
        }
        Ok(Self {
            data: data.cast(),
            len: 0,
            capacity: bound,
        })
    }

    /// Hands the mapping over without unmapping it.
    fn into_bytes(self) -> SnapitBytes {
        let this = ManuallyDrop::new(self);
        SnapitBytes {
            data: this.data,
            len: this.len,
            capacity: this.capacity,
        }
    }
}

impl Write for &mut MappedSink {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if self.len + buf.len() > self.capacity {
            return Err(io::ErrorKind::OutOfMemory.into());
        }
        // SAFETY: `len + buf.len()` is within the mapping, and `buf` cannot overlap it.
        unsafe { ptr::copy_nonoverlapping(buf.as_ptr(), self.data.add(self.len), buf.len()) };
        self.len += buf.len();
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl Drop for MappedSink {
    fn drop(&mut self) {
        // SAFETY: `data` and `capacity` describe the mapping `new` made.
        unsafe { libc::munmap(self.data.cast(), self.capacity) };
    }
}

fn encode_to_bytes(job: &Job, out: *mut SnapitBytes) -> SnapitStatus {
    let mut sink = match MappedSink::new(job) {
        Ok(sink) => sink,
        Err(e) => return e.status(),
    };
    if let Err(e) = encode_into(&mut sink, job) {
        return e.status();
    }
    // SAFETY: the caller guarantees `out` is writable.
    unsafe { out.write(sink.into_bytes()) };
    SNAPIT_STATUS_OK
}

/// Encodes premultiplied BGRA pixels as a PNG and stores the bytes in `out`: RGB when every pixel
/// is opaque, RGBA (colours un-premultiplied) when any is not.
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
    let params = SnapitPngParams {
        level,
        dpi,
        out_width: width,
        out_height: height,
        icc,
        icc_len,
    };
    // SAFETY: the caller's guarantees are the ones `snapit_png_encode_ex` asks for.
    unsafe { snapit_png_encode_ex(pixels, width, height, stride, &params, out) }
}

/// Like [`snapit_png_encode`], with the options in `params`. When `params.out_width` and
/// `out_height` are smaller than the source, the image is averaged down to that size (area
/// averaging) in the same pass as the encode: a 1x Export of a Retina Capture. The size must be
/// at least 1 and no larger than the source; a source of more than 65535 pixels either way can
/// only be encoded at its own size.
///
/// # Safety
///
/// `pixels` must be valid for reads of `(height - 1) * stride + width * 4` bytes, `params` for a
/// read (and its `icc` for `icc_len` bytes, when not null), and `out` for a write of one
/// `SnapitBytes`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_png_encode_ex(
    pixels: *const u8,
    width: u32,
    height: u32,
    stride: usize,
    params: *const SnapitPngParams,
    out: *mut SnapitBytes,
) -> SnapitStatus {
    guard(|| {
        if out.is_null() {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // SAFETY: the caller's guarantees are the ones `make_job` asks for.
        match unsafe { make_job(pixels, width, height, stride, params) } {
            Ok(job) => encode_to_bytes(&job, out),
            Err(status) => status,
        }
    })
}

/// Encodes like [`snapit_png_encode_ex`], but streams the PNG into the file `fd` through a
/// small buffer: the PNG is never held in memory, whatever its size. The engine writes from the
/// file's current position and leaves the descriptor open (and unflushed beyond the write); the
/// caller owns it. A failed write comes back as `SNAPIT_STATUS_IO_FAILED`.
///
/// # Safety
///
/// As for [`snapit_png_encode_ex`], and `fd` must be a file open for writing.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_png_encode_to_fd(
    pixels: *const u8,
    width: u32,
    height: u32,
    stride: usize,
    params: *const SnapitPngParams,
    fd: i32,
) -> SnapitStatus {
    guard(|| {
        if fd < 0 {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        // SAFETY: the caller's guarantees are the ones `make_job` asks for.
        let job = match unsafe { make_job(pixels, width, height, stride, params) } {
            Ok(job) => job,
            Err(status) => return status,
        };
        // SAFETY: the caller owns `fd`; wrapping it in `ManuallyDrop` keeps it from being closed.
        let file = ManuallyDrop::new(unsafe { File::from_raw_fd(fd) });
        let mut sink = BufWriter::with_capacity(256 * 1024, &*file);
        let result = encode_into(&mut sink, &job).and_then(|()| sink.flush().map_err(Into::into));
        match result {
            Ok(()) => SNAPIT_STATUS_OK,
            Err(e) => e.status(),
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
            // SAFETY: `data` and `capacity` describe a mapping the encoder made.
            unsafe { libc::munmap(b.data.cast(), b.capacity) };
        }
        b.data = ptr::null_mut();
        b.len = 0;
        b.capacity = 0;
        SNAPIT_STATUS_OK
    })
}
