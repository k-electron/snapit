import CoreGraphics
import Foundation
import Security

/// Where Screen Recording stands for snapit.
///
/// macOS only answers granted or not, so the other states are derived from what snapit
/// remembers: which build was granted before (it stays remembered across updates), whether it
/// has already asked, and whether it was granted when this process started.
enum ScreenRecordingState: String, Sendable {
    /// Never granted and never asked: macOS will show its prompt when snapit asks.
    case notDetermined
    /// Asked, and not granted: macOS does not ask again ("Don't Allow", or the switch is still
    /// off). Also a grant the user turned off for this very build.
    case denied
    case granted
    /// Granted before to another build, not granted now: an update is a new code identity to macOS,
    /// so the old entry no longer matches this copy.
    case grantedStale
    /// Granted now but not when this process started: macOS lets a process capture only from its
    /// next launch on, so snapit has to relaunch.
    case grantedNeedsRelaunch
}

/// Asks macOS whether snapit may record the screen. Always go through
/// `ScreenRecordingPermission.current`; never call the `CG…ScreenCaptureAccess` functions
/// directly. Only the menu bar app asks: the Editor helper is another bundle, and macOS would list
/// it as a second app. Its windows ask the menu bar app over the socket.
///
/// A Capture that finds Screen Recording missing must not call `request()` itself: after an update it
/// does nothing, because the old entry has to be reset first. It shows the Permission guide, which
/// asks through `ScreenRecordingAsk` (the `screen-recording-request` command).
protocol ScreenRecordingPermissionChecking {
    /// True when Screen Recording is granted and this process can use it. Never shows a prompt.
    var isGranted: Bool { get }
    var state: ScreenRecordingState { get }
    /// True when macOS had snapit granted Screen Recording before and the user has since turned it
    /// off for this same build.
    var wasTurnedOff: Bool { get }
    /// Asks macOS to show its Screen Recording prompt (first time only; later it does nothing).
    func request()
    /// Forgets that snapit was granted and that it asked, once its own entry has been reset.
    func forgetHistory()
}

enum ScreenRecordingPermission {
    static let current: any ScreenRecordingPermissionChecking =
        TestMode.isActive
        ? DerivedPermission(
            preflight: FixtureScreenRecording.isGranted, ask: FixtureScreenRecording.recordRequest,
            buildID: FixtureScreenRecording.buildID)
        : DerivedPermission(
            preflight: { CGPreflightScreenCaptureAccess() }, ask: { _ = CGRequestScreenCaptureAccess() },
            buildID: { BuildIdentity.current })
}

/// Which build of snapit this is, as macOS's privacy database tells builds apart. An ad-hoc signed
/// build is identified by its code directory hash, so every build is a new identity and an update
/// loses the grant. The bundle's build number stands in when the hash cannot be read.
enum BuildIdentity {
    static let current: String = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode
        {
            var information: CFDictionary?
            if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
                let dictionary = information as? [String: Any], let unique = dictionary[kSecCodeInfoUnique as String] as? Data
            {
                return "cdhash-" + unique.map { String(format: "%02x", $0) }.joined()
            }
        }
        return "build-" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
    }()
}

/// The states, derived the same way for macOS and for the fixture: only the inputs (`preflight`,
/// `ask`, `buildID`) differ, so the scripted run exercises the real derivation.
struct DerivedPermission: ScreenRecordingPermissionChecking {
    static let grantedBeforeKey = "screenRecordingGrantedBefore"
    static let grantedBuildKey = "screenRecordingGrantedBuild"
    static let requestedKey = "screenRecordingRequested"

    let preflight: @MainActor () -> Bool
    let ask: @MainActor () -> Void
    let buildID: @MainActor () -> String
    /// Whether macOS had granted snapit when this process started.
    private let grantedAtLaunch: Bool

    init(
        preflight: @escaping @MainActor () -> Bool, ask: @escaping @MainActor () -> Void,
        buildID: @escaping @MainActor () -> String
    ) {
        self.preflight = preflight
        self.ask = ask
        self.buildID = buildID
        grantedAtLaunch = preflight()
    }

    var isGranted: Bool { state == .granted }

    var wasTurnedOff: Bool {
        !preflight() && AppSetting.bool(Self.grantedBeforeKey, default: false)
            && AppDefaults.store.string(forKey: Self.grantedBuildKey) == buildID()
    }

    var state: ScreenRecordingState {
        if preflight() {
            remember()
            return grantedAtLaunch ? .granted : .grantedNeedsRelaunch
        }
        if AppSetting.bool(Self.grantedBeforeKey, default: false) {
            // The same build that was granted and is not now: the user turned it off.
            return AppDefaults.store.string(forKey: Self.grantedBuildKey) == buildID() ? .denied : .grantedStale
        }
        if AppSetting.bool(Self.requestedKey, default: false) { return .denied }
        return .notDetermined
    }

    /// Remembers that this build is granted.
    private func remember() {
        let build = buildID()
        if !AppSetting.bool(Self.grantedBeforeKey, default: false) { AppDefaults.store.set(true, forKey: Self.grantedBeforeKey) }
        if AppDefaults.store.string(forKey: Self.grantedBuildKey) != build {
            AppDefaults.store.set(build, forKey: Self.grantedBuildKey)
        }
    }

    func request() {
        AppDefaults.store.set(true, forKey: Self.requestedKey)
        ask()
    }

    func forgetHistory() {
        AppDefaults.store.removeObject(forKey: Self.grantedBeforeKey)
        AppDefaults.store.removeObject(forKey: Self.grantedBuildKey)
        AppDefaults.store.removeObject(forKey: Self.requestedKey)
    }
}

/// Test mode's macOS: whether it grants snapit is a flag in the run's defaults (granted until a
/// run says otherwise), and a request is a line in `<root>/screen-recording-requests`. No prompt
/// can ever show, and the real TCC database is never read. The build's identity is a value in the
/// defaults too, so a run can make this copy another build, as an update does.
enum FixtureScreenRecording {
    static let grantedKey = "test.screenRecordingGranted"
    static let buildKey = "test.screenRecordingBuild"
    static let defaultBuild = "build-1"

    static func isGranted() -> Bool { AppSetting.bool(grantedKey, default: true) }

    static func setGranted(_ granted: Bool) { AppDefaults.store.set(granted, forKey: grantedKey) }

    static func buildID() -> String { AppDefaults.store.string(forKey: buildKey) ?? defaultBuild }

    static func setBuildID(_ build: String) { AppDefaults.store.set(build, forKey: buildKey) }

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
