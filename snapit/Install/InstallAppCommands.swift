import Foundation

nonisolated extension SocketCommand {
    /// `install-check`: runs the launch check again and replies with its outcome (`none`,
    /// `move-screen-shown`, `fixed-in-place`, `not-approved`). Test mode only.
    static let installCheck = SocketCommand("install-check")
    /// `install-pretend-bundle <path>`: this process behaves as if it ran from `<path>`. Test mode only.
    static let installPretendBundle = SocketCommand("install-pretend-bundle")
    /// `install-fake-volume <path> <file system> <mounted from> <mount point> ro|rw`: `statfs`
    /// answers this for `<path>` and everything below it. Test mode only.
    static let installFakeVolume = SocketCommand("install-fake-volume")
    /// Forgets the pretended bundle path and the fake volumes. Test mode only.
    static let installReset = SocketCommand("install-reset")
    /// `install-detect <path>`: detection with the real `statfs` and `/Volumes`, same reply as
    /// `install-location`. Test mode only.
    static let installDetect = SocketCommand("install-detect")
}

extension SocketCommandRegistry {
    func registerInstallCommands() {
        register(.installLocation) { _ in
            let environment = InstallEdge.current
            let location = InstallCheck.location(environment: environment)
            return Self.describe(location, plan: location.plan(applicationsFolder: environment.applicationsFolder))
        }
        register(.moveToApplications) { _ in
            do {
                try await InstallCheck.moveChosen()
                return "ok"
            } catch {
                return "error \(error)"
            }
        }
        registerInstallTestCommands()
    }

    private func registerInstallTestCommands() {
        guard TestMode.isActive else { return }
        register(.installCheck) { _ in
            await InstallCheck.runAtLaunch().rawValue
        }
        register(.installPretendBundle) { request in
            guard let path = request.arguments.first, Self.isInsideRoot(path) else {
                return "error path must be inside the test root"
            }
            FixtureInstallEnvironment.shared.pretend(bundlePath: path)
            return "ok"
        }
        register(.installFakeVolume) { request in
            let arguments = request.arguments
            guard arguments.count == 5, Self.isInsideRoot(arguments[0]), arguments[4] == "ro" || arguments[4] == "rw"
            else { return "error install-fake-volume <path inside the root> <fs> <from> <mount> ro|rw" }
            FixtureInstallEnvironment.shared.addFakeVolume(
                pathPrefix: arguments[0],
                info: VolumeInfo(
                    fileSystem: arguments[1], mountedFrom: arguments[2], mountPoint: arguments[3],
                    isReadOnly: arguments[4] == "ro"))
            return "ok"
        }
        register(.installReset) { _ in
            FixtureInstallEnvironment.shared.reset()
            return "ok"
        }
        register(.installDetect) { request in
            guard let path = request.arguments.first else { return "error install-detect <path>" }
            let location = InstallLocation.detect(bundlePath: path, volumes: SystemVolumes(), volumesFolder: "/Volumes")
            return Self.describe(location, plan: location.plan(applicationsFolder: SystemInstallEnvironment.shared.applicationsFolder))
        }
    }

    private static func describe(_ location: InstallLocation, plan: InstallPlan) -> String {
        [
            "bundle=\(location.bundlePath)",
            "translocated=\(location.translocated)",
            "origin=\(location.originPath)",
            "on-disk-image=\(location.onDiskImage)",
            "mount=\(location.volume?.mountPoint ?? "unknown")",
            "decision=\(plan.name)",
        ].joined(separator: "\n")
    }

    private static func isInsideRoot(_ path: String) -> Bool {
        guard let root = TestMode.root.map({ RealPath.of($0.path) }), path.hasPrefix("/") else { return false }
        return RealPath.of(path).hasPrefix(root + "/")
    }
}
