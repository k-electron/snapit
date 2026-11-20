//! The 1x downscale, done in the same pass as the PNG encode, and the streamed output:
//! Save and drag-out write to a file descriptor, Copy takes bytes.

mod support;

use std::fs::File;
use std::os::fd::AsRawFd;
use std::ptr;

use snapit_engine::{
    SNAPIT_PNG_BALANCED, SNAPIT_PNG_FAST, SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_IO_FAILED,
    SNAPIT_STATUS_OK, SnapitPngParams, snapit_buffer_free, snapit_bytes_free, snapit_downscale,
    snapit_png_encode_ex, snapit_png_encode_to_fd,
};
use support::{alloc, bytes_of, chunk, chunks, decode_rgb, empty_bytes, fixture_bgra, fixture_rgb};

struct Image {
    pixels: Vec<u8>,
    width: u32,
    height: u32,
    stride: usize,
}

fn fixture(width: u32, height: u32, stride: usize) -> Image {
    Image {
        pixels: fixture_bgra(width, height, stride),
        width,
        height,
        stride,
    }
}

fn params(
    level: u32,
    dpi: u32,
    (out_width, out_height): (u32, u32),
    icc: &[u8],
) -> SnapitPngParams {
    SnapitPngParams {
        level,
        dpi,
        out_width,
        out_height,
        icc: if icc.is_empty() {
            ptr::null()
        } else {
            icc.as_ptr()
        },
        icc_len: icc.len(),
    }
}

fn encode_bytes(image: &Image, p: &SnapitPngParams) -> Vec<u8> {
    let mut out = empty_bytes();
    let status = unsafe {
        snapit_png_encode_ex(
            image.pixels.as_ptr(),
            image.width,
            image.height,
            image.stride,
            p,
            &mut out,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let png = bytes_of(&out).to_vec();
    assert_eq!(unsafe { snapit_bytes_free(&mut out) }, SNAPIT_STATUS_OK);
    assert!(out.data.is_null());
    png
}

/// Reference average, independent of the engine: every source pixel contributes its real-valued
/// overlap with the output pixel's footprint.
fn reference_average(image: &Image, (dw, dh): (u32, u32), x: u32, y: u32) -> [f64; 3] {
    let (sw, sh) = (f64::from(image.width), f64::from(image.height));
    let (fx, fy) = (sw / f64::from(dw), sh / f64::from(dh));
    let (x0, x1) = (f64::from(x) * fx, f64::from(x + 1) * fx);
    let (y0, y1) = (f64::from(y) * fy, f64::from(y + 1) * fy);
    let mut sum = [0.0; 3];
    let mut area = 0.0;
    for j in 0..image.height {
        let oy = ((f64::from(j) + 1.0).min(y1) - f64::from(j).max(y0)).max(0.0);
        if oy == 0.0 {
            continue;
        }
        for i in 0..image.width {
            let ox = ((f64::from(i) + 1.0).min(x1) - f64::from(i).max(x0)).max(0.0);
            if ox == 0.0 {
                continue;
            }
            let at = j as usize * image.stride + i as usize * 4;
            let (b, g, r) = (image.pixels[at], image.pixels[at + 1], image.pixels[at + 2]);
            for (s, c) in sum.iter_mut().zip([r, g, b]) {
                *s += ox * oy * f64::from(c);
            }
            area += ox * oy;
        }
    }
    sum.map(|s| s / area)
}

fn assert_close_to_reference(png: &[u8], image: &Image, size: (u32, u32)) {
    let (rgb, w, h) = decode_rgb(png);
    assert_eq!((w, h), size);
    for y in 0..h {
        for x in 0..w {
            let want = reference_average(image, size, x, y);
            let at = (y * w + x) as usize * 3;
            for c in 0..3 {
                let got = f64::from(rgb[at + c]);
                assert!(
                    (got - want[c]).abs() <= 0.5 + 1e-9,
                    "pixel {x},{y} channel {c}: got {got}, reference {}",
                    want[c]
                );
            }
        }
    }
}

#[test]
fn a_2x_export_halves_the_pixels_and_each_is_the_average_of_its_2x2_block() {
    // 602 x 374 is what a 301 x 187 point Retina Capture is; rows are padded.
    let image = fixture(602, 374, 2432);
    let p = params(SNAPIT_PNG_FAST, 72, (301, 187), &[]);
    let png = encode_bytes(&image, &p);

    let (rgb, w, h) = decode_rgb(&png);
    assert_eq!((w, h), (301, 187), "half the pixel size");
    for y in 0..h {
        for x in 0..w {
            // The average of the four source pixels, rounded half up.
            let mut want = [0u32; 3];
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let c = fixture_rgb(2 * x + dx, 2 * y + dy, 602, 374);
                for k in 0..3 {
                    want[k] += u32::from(c[k]);
                }
            }
            let at = (y * w + x) as usize * 3;
            for k in 0..3 {
                assert_eq!(
                    u32::from(rgb[at + k]),
                    (want[k] + 2) / 4,
                    "pixel {x},{y} channel {k}"
                );
            }
        }
    }
}

#[test]
fn a_1x_export_is_tagged_72_dpi_and_keeps_the_icc_profile() {
    let image = fixture(64, 48, 256);
    let profile: Vec<u8> = (0..1200u32).map(|i| (i * 13 % 251) as u8).collect();
    let p = params(SNAPIT_PNG_BALANCED, 72, (32, 24), &profile);
    let png = encode_bytes(&image, &p);

    let phys = chunk(&png, b"pHYs").expect("pHYs chunk");
    assert_eq!(u32::from_be_bytes(phys[0..4].try_into().unwrap()), 2835);
    assert_eq!(u32::from_be_bytes(phys[4..8].try_into().unwrap()), 2835);
    assert_eq!(phys[8], 1);
    let ihdr = chunk(&png, b"IHDR").unwrap();
    assert_eq!(u32::from_be_bytes(ihdr[0..4].try_into().unwrap()), 32);
    assert_eq!(u32::from_be_bytes(ihdr[4..8].try_into().unwrap()), 24);

    let reader = png::Decoder::new(std::io::Cursor::new(&png[..]))
        .read_info()
        .unwrap();
    assert_eq!(reader.info().icc_profile.as_deref(), Some(&profile[..]));
}

#[test]
fn other_ratios_average_by_area_and_odd_sizes_round_to_the_requested_size() {
    for (source, target) in [
        ((9, 6), (3, 2)),        // factor 3
        ((13, 9), (7, 5)),       // not a whole factor
        ((301, 187), (151, 94)), // the rounded half of an odd size
        ((5, 5), (5, 5)),        // factor 1
        ((12, 7), (1, 1)),       // down to one pixel
    ] {
        let image = fixture(source.0, source.1, source.0 as usize * 4 + 64);
        let p = params(SNAPIT_PNG_FAST, 72, target, &[]);
        let png = encode_bytes(&image, &p);
        assert_close_to_reference(&png, &image, target);
    }
}

#[test]
fn averaging_never_brightens_or_darkens() {
    // A flat image stays flat at any ratio: the weights sum to one in both directions.
    let mut image = fixture(37, 29, 37 * 4 + 12);
    for y in 0..29usize {
        for x in 0..37usize {
            let at = y * image.stride + x * 4;
            image.pixels[at..at + 4].copy_from_slice(&[10, 130, 250, 255]);
        }
    }
    for target in [(18, 14), (12, 10), (7, 3), (36, 28)] {
        let p = params(SNAPIT_PNG_FAST, 72, target, &[]);
        let (rgb, w, h) = decode_rgb(&encode_bytes(&image, &p));
        assert_eq!((w, h), target);
        assert!(rgb.chunks(3).all(|px| px == [250, 130, 10]));
    }
}

#[test]
fn a_downscaled_export_leaves_padding_out_of_the_average() {
    // Garbage padding (0xEE) after each row must never be averaged in.
    let image = fixture(20, 10, 20 * 4 + 200);
    assert!(image.pixels.contains(&0xEE));
    let p = params(SNAPIT_PNG_FAST, 72, (10, 5), &[]);
    assert_close_to_reference(&encode_bytes(&image, &p), &image, (10, 5));
}

#[test]
fn the_output_cannot_be_larger_than_the_source_or_empty() {
    let image = fixture(8, 8, 64);
    let mut out = empty_bytes();
    for size in [(9, 8), (8, 9), (0, 4), (4, 0), (0, 0)] {
        let p = params(SNAPIT_PNG_FAST, 72, size, &[]);
        let status = unsafe { snapit_png_encode_ex(image.pixels.as_ptr(), 8, 8, 64, &p, &mut out) };
        assert_eq!(status, SNAPIT_STATUS_INVALID_ARGUMENT, "{size:?}");
    }
    assert!(out.data.is_null());
}

#[test]
fn other_invalid_arguments_are_refused_with_a_status() {
    let image = fixture(8, 8, 64);
    let p = params(SNAPIT_PNG_FAST, 72, (4, 4), &[]);
    let mut out = empty_bytes();
    let px = image.pixels.as_ptr();
    let bad = SNAPIT_STATUS_INVALID_ARGUMENT;
    unsafe {
        assert_eq!(
            snapit_png_encode_ex(ptr::null(), 8, 8, 64, &p, &mut out),
            bad
        );
        assert_eq!(
            snapit_png_encode_ex(px, 8, 8, 64, ptr::null(), &mut out),
            bad
        );
        assert_eq!(snapit_png_encode_ex(px, 8, 8, 64, &p, ptr::null_mut()), bad);
        assert_eq!(
            snapit_png_encode_ex(px, 8, 8, 31, &p, &mut out),
            bad,
            "stride below a row"
        );
        assert_eq!(
            snapit_png_encode_to_fd(px, 8, 8, 64, &p, -1),
            bad,
            "no descriptor"
        );
        let zero_dpi = params(SNAPIT_PNG_FAST, 0, (4, 4), &[]);
        assert_eq!(snapit_png_encode_ex(px, 8, 8, 64, &zero_dpi, &mut out), bad);
        let unknown_level = params(7, 72, (4, 4), &[]);
        assert_eq!(
            snapit_png_encode_ex(px, 8, 8, 64, &unknown_level, &mut out),
            bad
        );
        // 65536 pixels is past what the averaging's arithmetic holds.
        let huge = SnapitPngParams {
            out_width: 100,
            out_height: 100,
            ..p
        };
        assert_eq!(
            snapit_png_encode_ex(px, 65536, 100, 262_144, &huge, &mut out),
            bad
        );
    }
    assert!(out.data.is_null());
}

#[test]
fn a_streamed_file_holds_the_same_png_as_the_bytes() {
    let image = fixture(301, 187, 1216);
    let profile: Vec<u8> = (0..900u32).map(|i| (i * 7 % 251) as u8).collect();
    for (target, level) in [
        ((301, 187), SNAPIT_PNG_BALANCED),
        ((151, 94), SNAPIT_PNG_FAST),
    ] {
        let p = params(level, 144, target, &profile);
        let bytes = encode_bytes(&image, &p);

        let dir = std::env::temp_dir().join(format!("snapit-engine-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("out.png");
        let file = File::create(&path).unwrap();
        let status = unsafe {
            snapit_png_encode_to_fd(
                image.pixels.as_ptr(),
                image.width,
                image.height,
                image.stride,
                &p,
                file.as_raw_fd(),
            )
        };
        assert_eq!(status, SNAPIT_STATUS_OK);
        // The engine leaves the descriptor open: the caller owns it, and still can use it.
        assert!(file.metadata().unwrap().len() > 0);
        drop(file);
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}

#[test]
fn a_write_that_fails_comes_back_as_an_io_status() {
    let image = fixture(64, 48, 256);
    let p = params(SNAPIT_PNG_FAST, 72, (64, 48), &[]);
    // A file opened for reading refuses every write.
    let file = File::open("/dev/null").unwrap();
    let status = unsafe {
        snapit_png_encode_to_fd(image.pixels.as_ptr(), 64, 48, 256, &p, file.as_raw_fd())
    };
    assert_eq!(status, SNAPIT_STATUS_IO_FAILED);
}

#[test]
fn balanced_and_fast_decode_to_the_same_pixels_and_balanced_is_smaller() {
    // A large enough Capture-like image for the levels to differ.
    let image = fixture(640, 400, 2560);
    let size = (640, 400);
    let fast = params(SNAPIT_PNG_FAST, 144, size, &[]);
    let balanced = params(SNAPIT_PNG_BALANCED, 144, size, &[]);
    let fast_png = encode_bytes(&image, &fast);
    let balanced_png = encode_bytes(&image, &balanced);
    assert_eq!(decode_rgb(&fast_png).0, decode_rgb(&balanced_png).0);
    assert!(
        balanced_png.len() < fast_png.len(),
        "Balanced {} bytes, Fast {} bytes",
        balanced_png.len(),
        fast_png.len()
    );
}

#[test]
fn the_output_bytes_are_page_backed_and_freed_back_to_the_os() {
    let image = fixture(256, 256, 1024);
    let p = params(SNAPIT_PNG_FAST, 72, (256, 256), &[]);
    let mut out = empty_bytes();
    let status =
        unsafe { snapit_png_encode_ex(image.pixels.as_ptr(), 256, 256, 1024, &p, &mut out) };
    assert_eq!(status, SNAPIT_STATUS_OK);
    assert_eq!(out.capacity % 4096, 0, "a whole number of pages");
    assert!(out.len <= out.capacity);
    assert_eq!(unsafe { snapit_bytes_free(&mut out) }, SNAPIT_STATUS_OK);
    assert!(out.data.is_null() && out.len == 0 && out.capacity == 0);
    // Freeing twice does nothing.
    assert_eq!(unsafe { snapit_bytes_free(&mut out) }, SNAPIT_STATUS_OK);
}

#[test]
fn a_thumbnail_is_the_same_average_written_as_bgra_into_a_buffer() {
    let image = fixture(602, 374, 2432);
    let mut dst = alloc(120, 75);
    let status = unsafe {
        snapit_downscale(
            image.pixels.as_ptr(),
            image.width,
            image.height,
            image.stride,
            120,
            75,
            dst.data,
            dst.stride,
            0,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let out = unsafe { std::slice::from_raw_parts(dst.data, dst.stride * 75) };
    for y in 0..75u32 {
        for x in 0..120u32 {
            let want = reference_average(&image, (120, 75), x, y);
            let at = y as usize * dst.stride + x as usize * 4;
            let (b, g, r, a) = (out[at], out[at + 1], out[at + 2], out[at + 3]);
            for (got, w) in [(r, want[0]), (g, want[1]), (b, want[2])] {
                assert!((f64::from(got) - w).abs() <= 0.5 + 1e-9, "pixel {x},{y}");
            }
            assert_eq!(a, 255);
        }
    }
    unsafe { snapit_buffer_free(&mut dst) };

    let bad = SNAPIT_STATUS_INVALID_ARGUMENT;
    let px = image.pixels.as_ptr();
    let mut tiny = [0u8; 16];
    unsafe {
        assert_eq!(
            snapit_downscale(px, 602, 374, 2432, 0, 4, tiny.as_mut_ptr(), 16, 0),
            bad
        );
        assert_eq!(
            snapit_downscale(px, 602, 374, 2432, 4, 4, ptr::null_mut(), 16, 0),
            bad
        );
        assert_eq!(
            snapit_downscale(px, 602, 374, 2432, 4, 4, tiny.as_mut_ptr(), 15, 0),
            bad
        );
        assert_eq!(
            snapit_downscale(px, 602, 374, 2432, 700, 4, tiny.as_mut_ptr(), 16, 0),
            bad
        );
    }
}

#[test]
fn chunk_walker_sees_one_header_and_one_end() {
    // Guards the helper the tests above rely on.
    let image = fixture(16, 16, 64);
    let p = params(SNAPIT_PNG_FAST, 72, (8, 8), &[]);
    let png = encode_bytes(&image, &p);
    let names: Vec<[u8; 4]> = chunks(&png).into_iter().map(|(k, _)| k).collect();
    assert_eq!(names.iter().filter(|n| *n == b"IHDR").count(), 1);
    assert_eq!(names.last(), Some(b"IEND"));
}

#[test]
fn a_sampled_thumbnail_reads_only_some_rows_and_stays_close_on_smooth_images() {
    // A vertical gradient: every row differs, so a sampled average is close but not exact.
    let (w, h) = (200usize, 1000usize);
    let stride = w * 4 + 64;
    let mut pixels = vec![0u8; stride * h];
    for y in 0..h {
        let v = (y * 255 / (h - 1)) as u8;
        for x in 0..w {
            pixels[y * stride + x * 4..][..4].copy_from_slice(&[v, v, v, 255]);
        }
    }
    let mut out = vec![0u8; 20 * 10 * 4];
    let status = unsafe {
        snapit_downscale(
            pixels.as_ptr(),
            w as u32,
            h as u32,
            stride,
            20,
            10,
            out.as_mut_ptr(),
            80,
            4,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    for y in 0..10usize {
        // The exact band average of a linear gradient is its value at the band's middle.
        let middle = (y * 100 + 50) as f64 * 255.0 / (h - 1) as f64;
        for x in 0..20usize {
            let got = f64::from(out[(y * 20 + x) * 4 + 2]);
            assert!(
                (got - middle).abs() <= 2.0,
                "pixel {x},{y}: {got} vs {middle}"
            );
        }
    }

    // Rows nobody samples are never read: poison every row except the ones a 4-sample thumbnail
    // takes (the middle of each quarter of a 100-row band) and the result does not change.
    let mut poisoned = pixels.clone();
    for y in 0..h {
        let band = y % 100;
        let sampled = [12, 37, 62, 87].contains(&band);
        if !sampled {
            for x in 0..w {
                poisoned[y * stride + x * 4..][..4].copy_from_slice(&[255, 0, 255, 255]);
            }
        }
    }
    let mut again = vec![0u8; 20 * 10 * 4];
    let status = unsafe {
        snapit_downscale(
            poisoned.as_ptr(),
            w as u32,
            h as u32,
            stride,
            20,
            10,
            again.as_mut_ptr(),
            80,
            4,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    assert_eq!(out, again, "only the sampled rows are read");
}
