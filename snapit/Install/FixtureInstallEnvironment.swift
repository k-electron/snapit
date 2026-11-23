import Foundation

/// Test mode's install environment. Applications is `<root>/Applications`, disk images mount
/// below `<root>/Volumes`, and the scripted run can make this process pretend it runs from a
/// fake volume or a translocated path. Volumes that were not faked are read with the real
/// `statfs`, so a relaunched copy under `<root>/Applications` detects itself for real. A fake
/// eject appends the mount point to `<root>/install/ejected` instead of calling `diskutil`.
final class FixtureInstallEnvironment: InstallEnvironment {
    static let shared = FixtureInstallEnvironment()

    private struct FakeVolume {
        var pathPrefix: String
        var info: VolumeInfo
    }

    private var fakeVolumes: [FakeVolume] = []
    private var pretendedBundlePath: String?

    private var root: URL { URL(fileURLWithPath: RealPath.of(TestMode.root?.path ?? "/nonexistent"), isDirectory: true) }

    var applicationsFolder: URL { root.appendingPathComponent("Applications", isDirectory: true) }
    var volumesFolder: String { root.appendingPathComponent("Volumes", isDirectory: true).path }
    var bundlePath: String { pretendedBundlePath ?? Bundle.main.bundlePath }

    var volumes: any VolumeInspecting {
        FakeVolumes(fakes: fakeVolumes.map { ($0.pathPrefix, $0.info) })
    }

    /// Where fake ejects are recorded.
    var ejectedMarker: URL? { TestMode.folder("install")?.appendingPathComponent("ejected") }

    func pretend(bundlePath path: String) { pretendedBundlePath = path }

    func addFakeVolume(pathPrefix: String, info: VolumeInfo) {
        fakeVolumes.append(FakeVolume(pathPrefix: pathPrefix, info: info))
    }

    func reset() {
        fakeVolumes = []
        pretendedBundlePath = nil
    }

    /// `<root>/update-staging`, new and empty: the run's root is on the volume Applications is on
    /// there, and a run can name the folder to see that nothing is left of the Update.
    func makeUpdateStagingFolder(forBundleAt bundle: URL) throws -> URL {
        let folder = root.appendingPathComponent("update-staging", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private let swapGate = FixtureGate()
    private var swapHeld = false

    /// `update-script hold-swap on|off`: while on, an Update waits just before its swap.
    func holdSwap(_ on: Bool) {
        swapHeld = on
        if !on { swapGate.release() }
    }

    func waitBeforeSwap() async {
        while swapHeld {
            do { try await swapGate.wait() } catch { return }
        }
    }

    func scheduleEject(mountPoint: String) {
        guard let marker = ejectedMarker else { return }
        let line = Data((mountPoint + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: marker) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: marker)
        }
    }

    /// Fake volumes first (longest matching path prefix wins), the real ones otherwise.
    private struct FakeVolumes: VolumeInspecting {
        var fakes: [(String, VolumeInfo)]

        func volume(at path: String) -> VolumeInfo? {
            let match = fakes.filter { path == $0.0 || path.hasPrefix($0.0 + "/") }.max { $0.0.count < $1.0.count }
            return match?.1 ?? SystemVolumes().volume(at: path)
        }
    }
}
