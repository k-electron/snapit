//! Tests drive the engine through the same C-ABI functions Swift calls.

use std::ffi::{CStr, c_char};
use std::ptr;

use snapit_engine::{
    SNAPIT_STATUS_BUFFER_TOO_SMALL, SNAPIT_STATUS_INVALID_ARGUMENT, SNAPIT_STATUS_OK,
    SNAPIT_STATUS_PANIC, SnapitStatus, snapit_engine_probe_panic, snapit_engine_version,
};

fn version_into(buf: &mut [u8]) -> (SnapitStatus, usize) {
    let mut len = 0usize;
    let status =
        unsafe { snapit_engine_version(buf.as_mut_ptr() as *mut c_char, buf.len(), &mut len) };
    (status, len)
}

#[test]
fn version_round_trips_through_the_c_abi() {
    let mut buf = [0u8; 32];
    let (status, len) = version_into(&mut buf);
    assert_eq!(status, SNAPIT_STATUS_OK);
    assert_eq!(buf[len], 0, "string is NUL terminated");
    let text = CStr::from_bytes_until_nul(&buf).unwrap().to_str().unwrap();
    assert_eq!(text.len(), len);
    assert_eq!(text, "0.1.0");
}

#[test]
fn too_small_buffer_reports_the_needed_length() {
    let mut buf = [0xAAu8; 3];
    let (status, len) = version_into(&mut buf);
    assert_eq!(status, SNAPIT_STATUS_BUFFER_TOO_SMALL);
    assert_eq!(len, 5);
    assert_eq!(buf, [0xAA; 3], "buffer is left untouched");
}

#[test]
fn null_pointers_are_invalid_arguments() {
    let mut len = 0usize;
    let status = unsafe { snapit_engine_version(ptr::null_mut(), 16, &mut len) };
    assert_eq!(status, SNAPIT_STATUS_INVALID_ARGUMENT);

    let mut buf = [0u8; 16];
    let status = unsafe {
        snapit_engine_version(buf.as_mut_ptr() as *mut c_char, buf.len(), ptr::null_mut())
    };
    assert_eq!(status, SNAPIT_STATUS_INVALID_ARGUMENT);
}

#[test]
fn a_panic_inside_the_engine_becomes_a_status_code() {
    assert_eq!(snapit_engine_probe_panic(), SNAPIT_STATUS_PANIC);
    // The engine keeps working after a panic.
    let mut buf = [0u8; 8];
    assert_eq!(version_into(&mut buf).0, SNAPIT_STATUS_OK);
}
