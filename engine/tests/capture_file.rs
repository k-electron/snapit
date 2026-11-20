//! The Capture file: a header, the display's ICC profile and the raw pixels, memory-mapped by
//! the menu bar app (writable) and by the Editor helper (read-only), through the C ABI.

mod support;

use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::os::fd::AsRawFd;
use std::path::PathBuf;
use std::ptr;

use snapit_engine::{
    SNAPIT_PIXEL_FORMAT_BGRA8_PREMULTIPLIED, SNAPIT_STATUS_BUFFER_TOO_SMALL,
    SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_INVALID_FILE, SNAPIT_STATUS_OK,
    SnapitCaptureHeader, SnapitPixelBuffer, snapit_buffer_free, snapit_capture_file_create,
    snapit_capture_file_icc, snapit_capture_file_info, snapit_capture_file_map,
};
use support::{fixture_bgra, fixture_rgb};

/// A temporary file that removes itself.
struct TempFile {
    path: PathBuf,
    file: File,
}

impl TempFile {
    fn new(name: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "snapit-engine-test-{}-{name}.pixels",
            std::process::id()
        ));
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(true)
            .open(&path)
            .unwrap();
        Self { path, file }
    }
    fn fd(&self) -> i32 {
        self.file.as_raw_fd()
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

fn empty_header() -> SnapitCaptureHeader {
    unsafe { std::mem::zeroed() }
}

fn empty_buffer() -> SnapitPixelBuffer {
    unsafe { std::mem::zeroed() }
}

/// Creates a Capture file of the fixture image and returns it, closed (unmapped).
fn write_fixture(file: &TempFile, width: u32, height: u32, icc: &[u8]) -> SnapitCaptureHeader {
    let mut header = empty_header();
    let mut buffer = empty_buffer();
    let status = unsafe {
        snapit_capture_file_create(
            file.fd(),
            width,
            height,
            2.0,
            1_700_000_123,
            icc.as_ptr(),
            icc.len(),
            &mut header,
            &mut buffer,
        )
    };
    assert_eq!(status, SNAPIT_STATUS_OK);
    let source = fixture_bgra(width, height, buffer.stride);
    unsafe {
        ptr::copy_nonoverlapping(
            source.as_ptr(),
            buffer.data,
            buffer.stride * height as usize,
        )
    };
    assert_eq!(unsafe { snapit_buffer_free(&mut buffer) }, SNAPIT_STATUS_OK);
    header
}

#[test]
fn pixels_written_by_one_mapping_are_read_back_by_another_with_the_metadata() {
    let file = TempFile::new("round-trip");
    let icc: Vec<u8> = (0..3000u32).map(|i| (i * 7) as u8).collect();
    let written = write_fixture(&file, 301, 187, &icc);
    assert!(written.stride >= 301 * 4);
    assert!(
        written.stride > 301 * 4,
        "301 px rows are padded, not tight"
    );

    // A second process opens the same file: info first, then a read-only mapping.
    let mut header = empty_header();
    assert_eq!(
        unsafe { snapit_capture_file_info(file.fd(), &mut header) },
        SNAPIT_STATUS_OK
    );
    assert_eq!((header.width, header.height), (301, 187));
    assert_eq!(header.stride, written.stride);
    assert_eq!(header.scale, 2.0);
    assert_eq!(header.capture_time, 1_700_000_123);
    assert_eq!(header.pixel_format, SNAPIT_PIXEL_FORMAT_BGRA8_PREMULTIPLIED);
    assert_eq!(header.icc_len, icc.len() as u64);

    let mut profile = vec![0u8; header.icc_len as usize];
    assert_eq!(
        unsafe { snapit_capture_file_icc(file.fd(), &header, profile.as_mut_ptr(), profile.len()) },
        SNAPIT_STATUS_OK
    );
    assert_eq!(profile, icc, "the profile comes back byte for byte");

    let mut buffer = empty_buffer();
    assert_eq!(
        unsafe { snapit_capture_file_map(file.fd(), &header, 0, &mut buffer) },
        SNAPIT_STATUS_OK
    );
    assert_eq!(
        (buffer.width, buffer.height, buffer.stride),
        (301, 187, header.stride)
    );
    let pixels =
        unsafe { std::slice::from_raw_parts(buffer.data, buffer.stride * buffer.height as usize) };
    for (x, y) in [
        (0, 0),
        (300, 0),
        (0, 186),
        (300, 186),
        (123, 77),
        (299, 100),
    ] {
        let at = y as usize * buffer.stride + x as usize * 4;
        let [r, g, b] = fixture_rgb(x, y, 301, 187);
        assert_eq!(&pixels[at..at + 4], &[b, g, r, 255], "pixel ({x}, {y})");
    }
    assert_eq!(unsafe { snapit_buffer_free(&mut buffer) }, SNAPIT_STATUS_OK);
}

#[test]
fn a_file_without_a_profile_is_valid() {
    let file = TempFile::new("no-icc");
    write_fixture(&file, 64, 8, &[]);
    let mut header = empty_header();
    assert_eq!(
        unsafe { snapit_capture_file_info(file.fd(), &mut header) },
        SNAPIT_STATUS_OK
    );
    assert_eq!(header.icc_len, 0);
}

#[test]
fn a_large_profile_pushes_the_pixels_to_a_later_page() {
    let file = TempFile::new("big-icc");
    let icc = vec![0x5A; 100_000];
    write_fixture(&file, 33, 5, &icc);
    let mut header = empty_header();
    assert_eq!(
        unsafe { snapit_capture_file_info(file.fd(), &mut header) },
        SNAPIT_STATUS_OK
    );
    assert!(header.pixel_offset >= 100_000 + 80);
    assert_eq!(
        header.pixel_offset % 4096,
        0,
        "pixels start on a page boundary"
    );
    let mut profile = vec![0u8; icc.len()];
    assert_eq!(
        unsafe { snapit_capture_file_icc(file.fd(), &header, profile.as_mut_ptr(), profile.len()) },
        SNAPIT_STATUS_OK
    );
    assert_eq!(profile, icc);
}

#[test]
fn the_helper_maps_a_file_it_only_opened_for_reading() {
    let file = TempFile::new("read-only");
    let header = write_fixture(&file, 16, 16, &[]);
    let reader = File::open(&file.path).unwrap();
    let mut buffer = empty_buffer();
    assert_eq!(
        unsafe { snapit_capture_file_map(reader.as_raw_fd(), &header, 0, &mut buffer) },
        SNAPIT_STATUS_OK
    );
    assert_eq!(unsafe { snapit_buffer_free(&mut buffer) }, SNAPIT_STATUS_OK);
    // A writable mapping of a file opened read-only is refused, not silently downgraded.
    assert_ne!(
        unsafe { snapit_capture_file_map(reader.as_raw_fd(), &header, 1, &mut buffer) },
        SNAPIT_STATUS_OK
    );
    assert!(
        buffer.data.is_null(),
        "a refused map leaves the buffer empty"
    );
}

#[test]
fn invalid_arguments_are_refused() {
    let file = TempFile::new("invalid");
    let mut header = empty_header();
    let mut buffer = empty_buffer();
    let create = |fd, w, h, scale, icc: *const u8, icc_len, header: *mut _, buffer: *mut _| unsafe {
        snapit_capture_file_create(fd, w, h, scale, 0, icc, icc_len, header, buffer)
    };
    assert_eq!(
        create(
            file.fd(),
            0,
            10,
            1.0,
            ptr::null(),
            0,
            &mut header,
            &mut buffer
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        create(
            file.fd(),
            10,
            0,
            1.0,
            ptr::null(),
            0,
            &mut header,
            &mut buffer
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        create(
            file.fd(),
            u32::MAX,
            u32::MAX,
            1.0,
            ptr::null(),
            0,
            &mut header,
            &mut buffer
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        create(
            file.fd(),
            10,
            10,
            0.0,
            ptr::null(),
            0,
            &mut header,
            &mut buffer
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        create(
            file.fd(),
            10,
            10,
            f64::NAN,
            ptr::null(),
            0,
            &mut header,
            &mut buffer
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        create(
            file.fd(),
            10,
            10,
            1.0,
            ptr::null(),
            5,
            &mut header,
            &mut buffer
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT,
        "a length without bytes"
    );
    assert_eq!(
        create(
            file.fd(),
            10,
            10,
            1.0,
            ptr::null(),
            0,
            ptr::null_mut(),
            &mut buffer
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        create(
            file.fd(),
            10,
            10,
            1.0,
            ptr::null(),
            0,
            &mut header,
            ptr::null_mut()
        ),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        create(-1, 10, 10, 1.0, ptr::null(), 0, &mut header, &mut buffer),
        SNAPIT_STATUS_INVALID_ARGUMENT
    );

    assert_eq!(
        unsafe { snapit_capture_file_info(file.fd(), ptr::null_mut()) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        unsafe { snapit_capture_file_info(-1, &mut header) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        unsafe { snapit_capture_file_map(file.fd(), ptr::null(), 0, &mut buffer) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        unsafe { snapit_capture_file_map(file.fd(), &header, 0, ptr::null_mut()) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        unsafe { snapit_capture_file_icc(file.fd(), ptr::null(), ptr::null_mut(), 0) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    // A header that describes no real file is damage, not a bad argument.
    assert_eq!(
        unsafe { snapit_capture_file_icc(file.fd(), &header, ptr::null_mut(), 0) },
        SNAPIT_STATUS_INVALID_FILE
    );
}

#[test]
fn the_profile_needs_a_buffer_that_holds_it() {
    let file = TempFile::new("icc-buffer");
    let header = write_fixture(&file, 16, 4, &[9; 500]);
    assert_eq!(
        unsafe { snapit_capture_file_icc(file.fd(), &header, ptr::null_mut(), 0) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    let mut small = [0u8; 499];
    assert_eq!(
        unsafe { snapit_capture_file_icc(file.fd(), &header, small.as_mut_ptr(), small.len()) },
        SNAPIT_STATUS_BUFFER_TOO_SMALL
    );
    assert!(small.iter().all(|&b| b == 0), "nothing is copied");
}

#[test]
fn damaged_files_are_refused_with_the_invalid_file_status() {
    // Empty file.
    let empty = TempFile::new("empty");
    let mut header = empty_header();
    assert_eq!(
        unsafe { snapit_capture_file_info(empty.fd(), &mut header) },
        SNAPIT_STATUS_INVALID_FILE
    );

    // Bad magic.
    let mut file = TempFile::new("bad-magic");
    write_fixture(&file, 32, 8, &[1, 2, 3]);
    file.file.seek(SeekFrom::Start(0)).unwrap();
    file.file.write_all(b"NOTSNAPI").unwrap();
    assert_eq!(
        unsafe { snapit_capture_file_info(file.fd(), &mut header) },
        SNAPIT_STATUS_INVALID_FILE
    );

    // Unknown version: the version field follows the 8 magic bytes.
    let mut file = TempFile::new("bad-version");
    write_fixture(&file, 32, 8, &[]);
    file.file.seek(SeekFrom::Start(8)).unwrap();
    file.file.write_all(&99u32.to_le_bytes()).unwrap();
    assert_eq!(
        unsafe { snapit_capture_file_info(file.fd(), &mut header) },
        SNAPIT_STATUS_INVALID_FILE
    );

    // Truncated: the pixels end before the header says they do. Mapping them would crash on
    // the first read past the end.
    let file = TempFile::new("truncated");
    let good = write_fixture(&file, 64, 64, &[]);
    file.file
        .set_len(good.pixel_offset + good.stride as u64 * 10)
        .unwrap();
    assert_eq!(
        unsafe { snapit_capture_file_info(file.fd(), &mut header) },
        SNAPIT_STATUS_INVALID_FILE
    );
    let mut buffer = empty_buffer();
    assert_eq!(
        unsafe { snapit_capture_file_map(file.fd(), &good, 0, &mut buffer) },
        SNAPIT_STATUS_INVALID_FILE,
        "a header the file does not back is refused at map time too"
    );
}
