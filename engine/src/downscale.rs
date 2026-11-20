//! Area-averaging downscale, one output row at a time.
//!
//! Every output pixel is the average of the source area it covers, each source pixel weighted
//! by how much of it falls inside that area. Weights are integers (the source and output
//! sizes are scaled to a common grid), so a 2x2 block averages exactly and a flat image stays
//! flat at any ratio. The filter streams: only one row of accumulators (`out_width * 3` words)
//! is ever held, never a buffer of the downscaled image, so the PNG encoder and the thumbnail
//! make their output in the same pass.

use std::slice;

use crate::buffer::SNAPIT_BYTES_PER_PIXEL;
use crate::{SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, SnapitStatus, guard};

/// Largest source width or height the integer arithmetic holds: every sum stays below 2^64.
pub(crate) const MAX_DOWNSCALE_SOURCE: u32 = 65_535;

/// The source pixels for one downscale: a BGRA image whose rows are `stride` bytes apart.
#[derive(Clone, Copy)]
pub(crate) struct Source<'a> {
    pub pixels: &'a [u8],
    pub width: usize,
    pub height: usize,
    pub stride: usize,
}

/// Which source pixels an output pixel covers, and how much of each.
struct Span {
    /// First source index.
    start: usize,
    /// Where its weights start in `Downscaler::weights`.
    weights: usize,
    /// How many source pixels it covers.
    count: usize,
}

/// The overlap, on the common grid, of source cell `i` (`i * out .. (i + 1) * out`) with output
/// cell `o` (`o * src .. (o + 1) * src`).
fn overlap(i: usize, o: usize, src: usize, out: usize) -> usize {
    ((i + 1) * out).min((o + 1) * src) - (i * out).max(o * src)
}

fn spans(src: usize, out: usize) -> (Vec<Span>, Vec<u32>) {
    let mut spans = Vec::with_capacity(out);
    let mut weights = Vec::with_capacity(src + out);
    for o in 0..out {
        let start = o * src / out;
        let last = ((o + 1) * src - 1) / out;
        spans.push(Span {
            start,
            weights: weights.len(),
            count: last - start + 1,
        });
        for i in start..=last {
            weights.push(overlap(i, o, src, out) as u32);
        }
    }
    (spans, weights)
}

pub(crate) struct Downscaler<'a> {
    source: Source<'a>,
    out_width: usize,
    out_height: usize,
    columns: Vec<Span>,
    column_weights: Vec<u32>,
    rows: Vec<Span>,
    row_weights: Vec<u32>,
    /// One source row, summed horizontally into output columns (3 channels each).
    horizontal: Vec<u32>,
    /// The output row being built.
    accumulator: Vec<u64>,
    /// At most this many source rows are read for each output row (evenly spaced, equally
    /// weighted); 0 reads them all. A preview does not need every row.
    max_row_samples: usize,
}

impl<'a> Downscaler<'a> {
    /// `source` and the output sizes were validated: output no larger than source, nothing zero,
    /// source within [`MAX_DOWNSCALE_SOURCE`].
    pub(crate) fn new(source: Source<'a>, out_width: usize, out_height: usize) -> Self {
        let (columns, column_weights) = spans(source.width, out_width);
        let (rows, row_weights) = spans(source.height, out_height);
        Self {
            source,
            out_width,
            out_height,
            columns,
            column_weights,
            rows,
            row_weights,
            horizontal: vec![0; out_width * 3],
            accumulator: vec![0; out_width * 3],
            max_row_samples: 0,
        }
    }

    /// Reads at most `samples` source rows per output row (0: all of them, the exact average).
    /// Only the rows read are touched, so a preview of a memory-mapped Capture leaves most of
    /// its pages unread.
    pub(crate) fn with_row_samples(mut self, samples: usize) -> Self {
        self.max_row_samples = samples;
        self
    }

    /// Writes output row `y` as RGB bytes (`out_width * 3` of them) into `rgb`.
    pub(crate) fn row_rgb(&mut self, y: usize, rgb: &mut [u8]) {
        debug_assert!(y < self.out_height && rgb.len() == self.out_width * 3);
        self.accumulator.fill(0);
        let (start, weights, count) = {
            let row = &self.rows[y];
            (row.start, row.weights, row.count)
        };
        let width = self.source.width as u64;
        let total = if self.max_row_samples > 0 && count > self.max_row_samples {
            let samples = self.max_row_samples;
            for i in 0..samples {
                self.add_source_row(start + (2 * i + 1) * count / (2 * samples), 1);
            }
            width * samples as u64
        } else {
            for (k, j) in (start..start + count).enumerate() {
                self.add_source_row(j, u64::from(self.row_weights[weights + k]));
            }
            width * self.source.height as u64
        };
        for (byte, sum) in rgb.iter_mut().zip(&self.accumulator) {
            *byte = ((sum + total / 2) / total) as u8;
        }
    }

    /// Adds source row `j`, weighted, into the output row being built.
    fn add_source_row(&mut self, j: usize, weight: u64) {
        self.sum_source_row(j);
        for (total, part) in self.accumulator.iter_mut().zip(&self.horizontal) {
            *total += weight * u64::from(*part);
        }
    }

    /// Sums source row `j` horizontally into `self.horizontal`, as R, G, B per output column.
    fn sum_source_row(&mut self, j: usize) {
        let row = &self.source.pixels[j * self.source.stride..]
            [..self.source.width * SNAPIT_BYTES_PER_PIXEL];
        let (outputs, _) = self.horizontal.as_chunks_mut::<3>();
        for (column, out) in self.columns.iter().zip(outputs) {
            let weights = &self.column_weights[column.weights..column.weights + column.count];
            let pixels = &row[column.start * SNAPIT_BYTES_PER_PIXEL..]
                [..column.count * SNAPIT_BYTES_PER_PIXEL];
            let (mut r, mut g, mut b) = (0u32, 0u32, 0u32);
            let (pixels, _) = pixels.as_chunks::<SNAPIT_BYTES_PER_PIXEL>();
            for (px, &w) in pixels.iter().zip(weights) {
                b += w * u32::from(px[0]);
                g += w * u32::from(px[1]);
                r += w * u32::from(px[2]);
            }
            *out = [r, g, b];
        }
    }
}

/// The number of bytes a `width` x `height` image with rows `stride` bytes apart spans (the last
/// row needs only its pixels), or `None` when a size is zero, the stride is below a row or
/// something overflows.
pub(crate) fn readable_len(width: u32, height: u32, stride: usize) -> Option<usize> {
    let row = (width as usize).checked_mul(SNAPIT_BYTES_PER_PIXEL)?;
    let len = (height as usize)
        .checked_sub(1)?
        .checked_mul(stride)?
        .checked_add(row)?;
    (stride >= row && len <= isize::MAX as usize).then_some(len)
}

/// True when `out_width` x `out_height` is a valid downscale target of the source size.
pub(crate) fn valid_target(width: u32, height: u32, out_width: u32, out_height: u32) -> bool {
    out_width > 0 && out_height > 0 && out_width <= width && out_height <= height
}

/// True when the source is small enough for the averaging (`out == source` needs no averaging
/// and is always fine).
pub(crate) fn within_averaging_limit(width: u32, height: u32) -> bool {
    width <= MAX_DOWNSCALE_SOURCE && height <= MAX_DOWNSCALE_SOURCE
}

/// Averages a BGRA image down to `out_width` x `out_height` and writes it as BGRA, opaque, into
/// `dst`, rows `dst_stride` bytes apart. For previews such as the drag-out thumbnail; the
/// averaging is the one the PNG encoder uses for a 1x Export.
///
/// `out_width` and `out_height` must be at least 1 and no larger than the source, and the source
/// no larger than 65535 pixels either way. `max_row_samples` limits how many source rows are read
/// for each output row (evenly spaced, equally weighted); 0 reads them all, which is the exact
/// average. A preview of a big Capture passes a small number, so most of the Capture's memory-mapped
/// pages are never read.
///
/// # Safety
///
/// `pixels` must be valid for reads of `(height - 1) * stride + width * 4` bytes and `dst` for
/// writes of `(out_height - 1) * dst_stride + out_width * 4` bytes; they must not overlap.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn snapit_downscale(
    pixels: *const u8,
    width: u32,
    height: u32,
    stride: usize,
    out_width: u32,
    out_height: u32,
    dst: *mut u8,
    dst_stride: usize,
    max_row_samples: u32,
) -> SnapitStatus {
    guard(|| {
        if pixels.is_null()
            || dst.is_null()
            || !valid_target(width, height, out_width, out_height)
            || !within_averaging_limit(width, height)
        {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        }
        let (Some(readable), Some(writable)) = (
            readable_len(width, height, stride),
            readable_len(out_width, out_height, dst_stride),
        ) else {
            return SNAPIT_STATUS_INVALID_ARGUMENT;
        };
        // SAFETY: the caller guarantees both ranges.
        let (pixels, dst) = unsafe {
            (
                slice::from_raw_parts(pixels, readable),
                slice::from_raw_parts_mut(dst, writable),
            )
        };
        let source = Source {
            pixels,
            width: width as usize,
            height: height as usize,
            stride,
        };
        let mut scaler = Downscaler::new(source, out_width as usize, out_height as usize)
            .with_row_samples(max_row_samples as usize);
        let mut rgb = vec![0u8; out_width as usize * 3];
        for y in 0..out_height as usize {
            scaler.row_rgb(y, &mut rgb);
            let row = &mut dst[y * dst_stride..][..out_width as usize * SNAPIT_BYTES_PER_PIXEL];
            let (out, _) = row.as_chunks_mut::<SNAPIT_BYTES_PER_PIXEL>();
            let (rgb, _) = rgb.as_chunks::<3>();
            for (px, c) in out.iter_mut().zip(rgb) {
                *px = [c[2], c[1], c[0], 255];
            }
        }
        SNAPIT_STATUS_OK
    })
}
