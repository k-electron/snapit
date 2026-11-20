import AppKit

enum InstallError: Error, CustomStringConvertible {
    /// macOS has not let this copy through Gatekeeper yet (no Open Anyway), so nothing is stripped.
    case notApproved(String)
    case copyFailed(String)
    case quarantineRemains
    case relaunchFailed(String)

    var description: String {
        switch self {
        case .notApproved(let path): "macOS has not approved \(path) yet. Open it with Open Anyway first."
        case .copyFailed(let reason): "snapit could not copy itself to Applications: \(reason)"
        case .quarantineRemains: "snapit could not remove the quarantine mark from its copy in Applications."
        case .relaunchFailed(let reason): "snapit could not relaunch from Applications: \(reason)"
        }
    }
}

/// The steps of "Move snapit to Applications" and of the in-place fix, in order:
/// copy, strip quarantine, relaunch, eject, quit. Quarantine is stripped only from an app the
/// user has approved with Open Anyway (`Quarantine.isApproved`), and the relaunch happens only
/// once no item in the copy carries quarantine any more, so Gatekeeper never blocks the
/// relaunched copy.
@MainActor
enum MoveToApplications {
    /// Copies `source` into Applications (replacing a copy that is already there), strips
    /// quarantine from the copy, relaunches from it, schedules the eject of a disk image and quits.
    static func move(source: URL, environment: any InstallEnvironment) async throws {
        guard Quarantine.isApproved(at: source.path) else { throw InstallError.notApproved(source.path) }
        let fileManager = FileManager.default
        let applications = environment.applicationsFolder
        let destination = applications.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        let staged = applications.appendingPathComponent(".snapit-move-\(getpid())", isDirectory: true)

        // The copy is staged beside its destination, so a failed copy never costs the user the
        // snapit that is already in Applications.
        do {
            try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: staged)
            try fileManager.copyItem(at: source, to: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw InstallError.copyFailed(error.localizedDescription)
        }
        Quarantine.strip(under: staged)
        guard Quarantine.flaggedCount(under: staged) == 0 else {
            try? fileManager.removeItem(at: staged)
            throw InstallError.quarantineRemains
        }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                terminateRunningCopies(at: destination)
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staged)
            throw InstallError.copyFailed(error.localizedDescription)
        }

        let mountPoint = diskImageMountPoint(of: source, environment: environment)
        try await relaunchAndQuit(appAt: destination, ejecting: mountPoint, environment: environment)
    }

    /// Strips quarantine from `copy` in place and relaunches it.
    static func fixInPlace(copy: URL, environment: any InstallEnvironment) async throws {
        guard Quarantine.isApproved(at: copy.path) else { throw InstallError.notApproved(copy.path) }
        Quarantine.strip(under: copy)
        guard Quarantine.flaggedCount(under: copy) == 0 else { throw InstallError.quarantineRemains }
        try await relaunchAndQuit(appAt: copy, ejecting: nil, environment: environment)
    }

    private static func relaunchAndQuit(
        appAt url: URL, ejecting mountPoint: String?, environment: any InstallEnvironment
    ) async throws {
        SocketOwnership.release()
        do {
            try await InstallRelaunch.start(appAt: url)
        } catch {
            SocketOwnership.reacquire()
            throw InstallError.relaunchFailed(error.localizedDescription)
        }
        if let mountPoint { environment.scheduleEject(mountPoint: mountPoint) }
        InstallRelaunch.quitSoon()
    }

    /// The mount point of the disk image `source` sits on, or nil when it is not on one.
    private static func diskImageMountPoint(of source: URL, environment: any InstallEnvironment) -> String? {
        let location = InstallLocation.detect(
            bundlePath: source.path, volumes: environment.volumes, volumesFolder: environment.volumesFolder)
        return location.onDiskImage ? location.volume?.mountPoint : nil
    }

    /// Quits every other running snapit that runs from `url`.
    private static func terminateRunningCopies(at url: URL) {
        let target = RealPath.of(url.path)
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.mainBundleIdentifier)
        where app.processIdentifier != getpid() && app.bundleURL.map({ RealPath.of($0.path) }) == target {
            app.terminate()
        }
    }
}
