import AppKit

/// Everything the install location check and the move touch outside the process: where this
/// copy runs from, which volumes exist, where Applications is, and the steps that relaunch,
/// eject and quit. Always go through `InstallEdge.current`. Test mode swaps in
/// `FixtureInstallEnvironment`, whose paths, volumes and eject live in the run's root.
protocol InstallEnvironment: AnyObject {
    /// The folder the app is moved into (`/Applications`).
    var applicationsFolder: URL { get }
    /// Disk images mount below this folder (`/Volumes`).
    var volumesFolder: String { get }
    var volumes: any VolumeInspecting { get }
    /// Where this copy of snapit runs from.
    var bundlePath: String { get }
    /// Ejects the disk image mounted at `mountPoint` once this process has quit.
    func scheduleEject(mountPoint: String)
}

enum InstallEdge {
    static var current: any InstallEnvironment {
        TestMode.isActive ? FixtureInstallEnvironment.shared : SystemInstallEnvironment.shared
    }
}

/// The menu bar app gives up its command socket while it relaunches: a second snapit that finds
/// the socket answering quits at once, so the relaunched copy could never take over.
enum SocketOwnership {
    private static var server: CommandSocketServer?

    /// The server that owns the command socket.
    static func adopt(_ server: CommandSocketServer) { self.server = server }

    static func release() { server?.stop() }

    static func reacquire() {
        do { try server?.start() } catch { NSLog("snapit: command socket failed to restart: \(error)") }
    }
}

/// Relaunch and quit are the same for the real system and the fixture: the fixture relaunches
/// a real copy, which keeps the test root.
enum InstallRelaunch {
    /// Starts a new instance of the app at `url`.
    static func start(appAt url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        // A scripted run must not take focus from what the user is doing.
        configuration.activates = !TestMode.isActive
        if let root = TestMode.root { configuration.environment = [TestMode.rootVariable: root.path] }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Quits this process a moment later, so the reply to the helper gets out first.
    static func quitSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApplication.shared.terminate(nil) }
    }
}

final class SystemInstallEnvironment: InstallEnvironment {
    static let shared = SystemInstallEnvironment()

    var applicationsFolder: URL { URL(fileURLWithPath: "/Applications", isDirectory: true) }
    var volumesFolder: String { "/Volumes" }
    var volumes: any VolumeInspecting { SystemVolumes() }
    var bundlePath: String { Bundle.main.bundlePath }

    /// The volume stays busy while this process or its helper runs from it, so a detached shell
    /// ejects it after both have quit. Only a mounted disk image is ejected: `hdiutil info` must
    /// list the mount point.
    func scheduleEject(mountPoint: String) {
        let script = """
            mount="$1"; shift
            for pid in "$0" "$@"; do while kill -0 "$pid" 2>/dev/null; do sleep 0.3; done; done
            /usr/bin/hdiutil info 2>/dev/null | /usr/bin/grep -qF "$mount" || exit 0
            sleep 1
            /usr/sbin/diskutil eject "$mount" >/dev/null 2>&1 || { sleep 2; /usr/sbin/diskutil eject "$mount" >/dev/null 2>&1; }
            """
        let helpers = NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.editorBundleIdentifier)
            .filter { $0.bundleURL?.path.hasPrefix(Bundle.main.bundlePath + "/") == true }
            .map { String($0.processIdentifier) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, String(getpid()), mountPoint] + helpers
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("snapit: could not schedule the eject of \(mountPoint): \(error)") }
    }
}
