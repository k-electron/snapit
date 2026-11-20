import CoreGraphics

/// Asks macOS whether snapit may record the screen. Always go through
/// `ScreenRecordingPermission.current`; never call the `CG…ScreenCaptureAccess` functions
/// directly.
protocol ScreenRecordingPermissionChecking {
    /// True when Screen Recording is granted. Never shows a prompt.
    var isGranted: Bool { get }
    /// Asks macOS to show its Screen Recording prompt (first time only; later it does nothing).
    func request()
}

enum ScreenRecordingPermission {
    static let current: any ScreenRecordingPermissionChecking =
        TestMode.isActive ? GrantedPermission() : SystemPermission()
}

private struct SystemPermission: ScreenRecordingPermissionChecking {
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    func request() { _ = CGRequestScreenCaptureAccess() }
}

/// Test mode: always granted, and asking does nothing, so no run can trigger a real prompt.
private struct GrantedPermission: ScreenRecordingPermissionChecking {
    var isGranted: Bool { true }
    func request() {}
}
