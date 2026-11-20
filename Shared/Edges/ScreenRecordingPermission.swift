import CoreGraphics
import Foundation

/// Where Screen Recording stands for snapit.
///
/// macOS only answers granted or not, so the other states are derived from what snapit
/// remembers: whether it was granted before (it stays remembered across updates) and whether it
/// has already asked.
enum ScreenRecordingState: String, Sendable {
    /// Never granted and never asked: macOS will show its prompt when snapit asks.
    case notDetermined
    /// Asked, and not granted: macOS does not ask again ("Don't Allow", or the switch is still off).
    case denied
    case granted
    /// Granted before, not granted now: an update is a new code identity to macOS, so the old
    /// entry no longer matches this copy.
    case grantedStale
}

/// Asks macOS whether snapit may record the screen. Always go through
/// `ScreenRecordingPermission.current`; never call the `CG…ScreenCaptureAccess` functions
/// directly. Only the menu bar app asks: the Editor helper is another bundle, and macOS would list
/// it as a second app. Its windows ask the menu bar app over the socket.
protocol ScreenRecordingPermissionChecking {
    /// True when Screen Recording is granted. Never shows a prompt.
    var isGranted: Bool { get }
    var state: ScreenRecordingState { get }
    /// Asks macOS to show its Screen Recording prompt (first time only; later it does nothing).
    func request()
    /// Forgets that snapit was granted and that it asked, once its own entry has been reset.
    func forgetHistory()
}

enum ScreenRecordingPermission {
    static let current: any ScreenRecordingPermissionChecking =
        TestMode.isActive
        ? DerivedPermission(preflight: FixtureScreenRecording.isGranted, ask: FixtureScreenRecording.recordRequest)
        : DerivedPermission(preflight: { CGPreflightScreenCaptureAccess() }, ask: { _ = CGRequestScreenCaptureAccess() })
}

/// The four states, derived the same way for macOS and for the fixture: only the two inputs
/// (`preflight`, `ask`) differ, so the scripted run exercises the real derivation.
struct DerivedPermission: ScreenRecordingPermissionChecking {
    static let grantedBeforeKey = "screenRecordingGrantedBefore"
    static let requestedKey = "screenRecordingRequested"

    let preflight: @MainActor () -> Bool
    let ask: @MainActor () -> Void

    var isGranted: Bool {
        guard preflight() else { return false }
        if !AppSetting.bool(Self.grantedBeforeKey, default: false) {
            AppDefaults.store.set(true, forKey: Self.grantedBeforeKey)
        }
        return true
    }

    var state: ScreenRecordingState {
        if isGranted { return .granted }
        if AppSetting.bool(Self.grantedBeforeKey, default: false) { return .grantedStale }
        if AppSetting.bool(Self.requestedKey, default: false) { return .denied }
        return .notDetermined
    }

    func request() {
        AppDefaults.store.set(true, forKey: Self.requestedKey)
        ask()
    }

    func forgetHistory() {
        AppDefaults.store.removeObject(forKey: Self.grantedBeforeKey)
        AppDefaults.store.removeObject(forKey: Self.requestedKey)
    }
}

/// Test mode's macOS: whether it grants snapit is a flag in the run's defaults (granted until a
/// run says otherwise), and a request is a line in `<root>/screen-recording-requests`. No prompt
/// can ever show, and the real TCC database is never read.
enum FixtureScreenRecording {
    static let grantedKey = "test.screenRecordingGranted"

    static func isGranted() -> Bool { AppSetting.bool(grantedKey, default: true) }

    static func setGranted(_ granted: Bool) { AppDefaults.store.set(granted, forKey: grantedKey) }

    static var requestsLog: URL? { TestMode.root?.appendingPathComponent("screen-recording-requests") }

    static func recordRequest() {
        guard let log = requestsLog else { return }
        append("request\n", to: log)
    }

    static func append(_ line: String, to file: URL) {
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    /// How many lines `file` holds.
    static func lineCount(_ file: URL?) -> Int {
        guard let file, let text = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }
}
