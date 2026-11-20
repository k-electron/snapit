//! Engine-owned pixel memory, through the C ABI.

mod support;

use std::ptr;

use snapit_engine::{
    SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK, SnapitPixelBuffer, snapit_buffer_alloc,
    snapit_buffer_free,
};
use support::alloc;

#[test]
fn a_buffer_is_zeroed_page_backed_memory_with_a_stride_that_covers_the_row() {
    let mut buffer = alloc(301, 187);
    assert_eq!((buffer.width, buffer.height), (301, 187));
    assert!(buffer.stride >= 301 * 4, "stride covers the row");
    assert_eq!(buffer.stride % 64, 0, "rows start on a 64 byte boundary");
    assert!(buffer.stride > 301 * 4, "301 px rows are padded, not tight");
    assert!(buffer.mapped_len >= buffer.stride * 187);
    assert_eq!(buffer.mapped_len % 4096, 0, "whole pages");

    let bytes = unsafe { std::slice::from_raw_parts(buffer.data, buffer.stride * 187) };
    assert!(bytes.iter().all(|&b| b == 0), "fresh pages read as zero");

    assert_eq!(unsafe { snapit_buffer_free(&mut buffer) }, SNAPIT_STATUS_OK);
    assert!(buffer.data.is_null());
    assert_eq!(buffer.mapped_len, 0);
}

#[test]
fn freeing_twice_is_harmless() {
    let mut buffer = alloc(16, 16);
    assert_eq!(unsafe { snapit_buffer_free(&mut buffer) }, SNAPIT_STATUS_OK);
    assert_eq!(unsafe { snapit_buffer_free(&mut buffer) }, SNAPIT_STATUS_OK);
}

#[test]
fn invalid_sizes_and_pointers_are_refused() {
    let mut buffer = alloc(1, 1);
    for (w, h) in [(0, 10), (10, 0), (u32::MAX, u32::MAX)] {
        let status = unsafe { snapit_buffer_alloc(w, h, &mut buffer) };
        assert_eq!(status, SNAPIT_STATUS_INVALID_ARGUMENT, "{w}x{h}");
    }
    assert_eq!(
        unsafe { snapit_buffer_alloc(10, 10, ptr::null_mut()) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    assert_eq!(
        unsafe { snapit_buffer_free(ptr::null_mut::<SnapitPixelBuffer>()) },
        SNAPIT_STATUS_INVALID_ARGUMENT
    );
    unsafe { snapit_buffer_free(&mut buffer) };
}
