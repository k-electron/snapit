import Foundation

/// The seam between snapit and the real system for the scripted whole-app run.
///
/// The scripted run (`scripts/check-run.sh`) sets `SNAPIT_TEST_ROOT` to a fresh temporary
/// folder before it starts either process. While it is set, every edge that would touch the
/// real system reads its replacement instead:
///
/// | Edge | Real | Test mode | Where |
/// |---|---|---|---|
/// | cache folder and sockets | `~/Library/Caches/dev.snapit.snapit` | the root | `AppIdentity` |
/// | Capture source | ScreenCaptureKit | fixture images | `snapit/Capture/CaptureSource.swift` |
/// | Screen Recording permission | `CGPreflightScreenCaptureAccess` | granted | `Shared/Edges/ScreenRecordingPermission.swift` |
/// | pasteboard | the general pasteboard | a private named pasteboard | `Shared/Edges/AppPasteboard.swift` |
/// | Save location | `~/Downloads` | `<root>/save` | `Shared/Edges/SaveLocation.swift` |
/// | defaults | the bundle ID's `UserDefaults` | a plist inside the root | `Shared/Edges/AppDefaults.swift` |
/// | Shortcuts | Carbon hot keys | injected events | `snapit/Shortcuts/ShortcutRegistrar.swift` |
///
/// An edge is one file: a protocol (or a small enum), its real implementation, and the
/// choice between real and fixture in one place. A feature that needs a new edge adds a new
/// file like that and its own test-mode commands (`docs/development/testing.md` has the recipe), so no
/// shared file changes.
nonisolated enum TestMode {
    static let rootVariable = "SNAPIT_TEST_ROOT"

    /// The per-run temporary root, or nil in a normal run.
    static let root: URL? = {
        guard let path = ProcessInfo.processInfo.environment[rootVariable], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    static var isActive: Bool { root != nil }

    /// A name unique to this run (the root's folder name). Names of per-run system
    /// resources, such as the private pasteboard, derive from it so two runs never collide.
    static var runID: String? { root?.lastPathComponent }

    /// A folder inside the per-run root, created on first use. Nil in a normal run.
    static func folder(_ name: String) -> URL? {
        guard let root else { return nil }
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
