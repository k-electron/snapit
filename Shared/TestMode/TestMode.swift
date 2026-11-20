import Foundation

/// The seam between snapit and the real system for the scripted whole-app run.
///
/// The scripted run sets `SNAPIT_TEST_ROOT` to a fresh temporary folder before it starts
/// either process. While it is set, anything that would touch the real system (the
/// private cache folder and the sockets in it, and later the Capture source, permission
/// checks, pasteboard, Save location and defaults) reads its replacement from here.
/// Each later feature adds its own `extension TestMode` in its own file.
enum TestMode {
    static let rootVariable = "SNAPIT_TEST_ROOT"

    /// The per-run temporary root, or nil in a normal run.
    static let root: URL? = {
        guard let path = ProcessInfo.processInfo.environment[rootVariable], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    static var isActive: Bool { root != nil }
}
