import Foundation

/// An Update, in the menu bar app: replaces the running snapit with the release the Update window
/// announced, and relaunches. The Editor helper asks for it (`install-update`) and shows what it
/// is doing; this does the work, in this order:
///
/// 1. Download the release's `snapit-X.Y.Z.dmg` and `snapit-X.Y.Z.dmg.sha256` into a staging folder
///    on the volume the installed copy is on.
/// 2. Check the disk image against the published SHA-256, attach it read-only and hidden, copy
///    `snapit.app` out of it, detach it, and clear any quarantine on the copy.
/// 3. Swap the staged copy in at the installed copy's path, while snapit and the helper still run.
///    Nothing before this step touches the installed copy, so a failure up to here leaves it as it
///    was, and the staging folder is removed.
/// 4. Relaunch the swapped-in copy through `SnapitRelaunch`, which hands it the Last Capture and
///    the staging folder (holding the old copy); the new copy deletes that folder.
@MainActor
enum UpdateInstall {
    nonisolated enum Failure: Error, CustomStringConvertible {
        /// The Update window announced a version this copy does not know of, or none.
        case notAnnounced
        case alreadyRunning
        case staging(String)
        case network(ReleaseEndpointError)
        case status(Int)
        case notAHash
        case hashMismatch
        case diskImage(String)
        case quarantineRemains

        /// One word for the cause, which the reply of `install-update` leads with; the Update window
        /// words each one for the user.
        var code: String {
            switch self {
            case .notAnnounced: "not-announced"
            case .alreadyRunning: "already-running"
            case .staging: "staging"
            case .network: "network"
            case .status: "status"
            case .notAHash: "not-a-hash"
            case .hashMismatch: "hash-mismatch"
            case .diskImage: "disk-image"
            case .quarantineRemains: "quarantine"
            }
        }

        var description: String {
            switch self {
            case .notAnnounced: "no newer release was announced"
            case .alreadyRunning: "an Update is already running"
            case .staging(let reason): "snapit could not make room to update: \(reason)"
            case .network(let error): "GitHub could not be reached (\(error))"
            case .status(let code): "GitHub answered \(code)"
            case .notAHash: "the release's hash file is not a hash"
            case .hashMismatch: "the download does not match the release's hash"
            case .diskImage(let reason): reason
            case .quarantineRemains: "snapit could not clear quarantine from the new copy"
            }
        }
    }

    private static var isRunning = false

    /// The reply of `install-update <version>`: `ok` once the new copy has been started (the old
    /// one quits a moment later), or `error <cause> <description>` with the installed copy as it was.
    static func run(announcing version: String, environment: any InstallEnvironment = InstallEdge.current) async -> String {
        guard !isRunning else { return failureReply(Failure.alreadyRunning) }
        isRunning = true
        defer { isRunning = false }
        let bundle = URL(fileURLWithPath: environment.bundlePath, isDirectory: true)
        let staging: URL
        do {
            staging = try await install(announcing: version, over: bundle, environment: environment)
        } catch {
            NSLog("snapit: Update stopped before the swap: \(error)")
            return failureReply(error)
        }
        let reply = await SnapitRelaunch.run(appAt: bundle, updateStagingFolder: staging)
        // A relaunch that did not start leaves this copy running; the old copy has no use in staging.
        if reply != "ok" {
            NSLog("snapit: Update swapped the new copy in but could not relaunch: \(reply)")
            try? FileManager.default.removeItem(at: staging)
        }
        return reply
    }

    /// `error <cause> <description>`: the cause is one word (`Failure.code`, `swap` for a swap that
    /// failed, `unknown`), the description is for the log.
    private static func failureReply(_ error: Error) -> String {
        if let failure = error as? Failure { return "error \(failure.code) \(failure)" }
        if let swap = error as? BundleSwap.Failure { return "error swap \(swap)" }
        return "error unknown \(error)"
    }

    /// Steps 1 to 3. Returns the staging folder, which then holds the old copy.
    private static func install(
        announcing version: String, over bundle: URL, environment: any InstallEnvironment
    ) async throws -> URL {
        guard let release = UpdateCheck.announced, release.version == version,
            let imageRequest = release.diskImageRequest, let hashRequest = release.hashRequest
        else { throw Failure.notAnnounced }
        let staging: URL
        do {
            staging = try environment.makeUpdateStagingFolder(forBundleAt: bundle)
        } catch {
            throw Failure.staging(error.localizedDescription)
        }
        do {
            let image = staging.appendingPathComponent(release.diskImageName)
            let staged = staging.appendingPathComponent("snapit.app", isDirectory: true)
            try await download(imageRequest, hashRequest, to: image)
            try await Task.detached { try extractApp(from: image, to: staged, in: staging) }.value
            try BundleSwap.swap(staged: staged, intoPlaceOf: bundle)
            return staging
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// The release's hash file and disk image, and whether the image is the one the hash names.
    private static func download(
        _ imageRequest: ReleaseRequest, _ hashRequest: ReleaseRequest, to image: URL
    ) async throws {
        let endpoint = ReleaseEndpoints.current
        let published: String
        do {
            let response = try await endpoint.fetch(hashRequest)
            guard response.status == 200 else { throw Failure.status(response.status) }
            guard let hash = DiskImage.publishedHash(in: response.body) else { throw Failure.notAHash }
            published = hash
            let status = try await endpoint.download(imageRequest, to: image)
            guard status == 200 else { throw Failure.status(status) }
        } catch let error as ReleaseEndpointError {
            throw Failure.network(error)
        }
        let actual = try await Task.detached { try DiskImage.sha256(of: image) }.value
        guard actual == published else { throw Failure.hashMismatch }
    }

    /// Copies `snapit.app` out of the disk image into `staged`, clears quarantine on the copy and
    /// deletes the image. Blocks, so it runs off the main actor.
    private nonisolated static func extractApp(from image: URL, to staged: URL, in staging: URL) throws {
        do {
            try DiskImage.copyApp(from: image, to: staged, mountingAt: staging.appendingPathComponent("volume", isDirectory: true))
        } catch let failure as DiskImage.Failure {
            throw Failure.diskImage("\(failure)")
        }
        Quarantine.strip(under: staged)
        guard Quarantine.flaggedCount(under: staged) == 0 else { throw Failure.quarantineRemains }
        try? FileManager.default.removeItem(at: image)
    }
}
