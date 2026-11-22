import Foundation

/// An Update, in the menu bar app: replaces the running snapit with the release the Update window
/// announced, and relaunches. The Editor helper asks for it (`install-update`) and shows what it
/// is doing; this does the work, in this order:
///
/// 1. Download the release's `snapit-X.Y.Z.dmg` and `snapit-X.Y.Z.dmg.sha256` into a staging folder
///    on the volume the installed copy is on. The helper reads the progress (`update-status`).
/// 2. Check the disk image against the published SHA-256, attach it read-only and hidden, copy
///    `snapit.app` out of it, detach it, and clear any quarantine on the copy.
/// 3. Swap the staged copy in at the installed copy's path, while snapit and the helper still run.
///    Nothing before this step touches the installed copy, so a failure up to here leaves it as it
///    was, and the staging folder is removed. The swap begins by cancelling what snapit has in
///    progress (a Timed Capture counting down).
///
/// The Update can be cancelled (`cancel-update`) until the swap begins: it then stops with nothing
/// changed and nothing left in the staging folder, which is removed. From the swap on, a cancel is refused.
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
        /// The user cancelled, or closed the Update window, before the swap began.
        case cancelled

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
            case .cancelled: "cancelled"
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
            case .cancelled: "the Update was cancelled"
            }
        }
    }

    private static var running: Task<String, Never>?
    /// How far the running Update has got; the helper reads it (`update-status`).
    private(set) static var progress = UpdateProgress.idle

    /// The reply of `install-update <version>`: `ok` once the new copy has been started (the old
    /// one quits a moment later), or `error <cause> <description>` with the installed copy as it was.
    static func run(announcing version: String, environment: any InstallEnvironment = InstallEdge.current) async -> String {
        guard running == nil else { return failureReply(Failure.alreadyRunning) }
        let task = Task { @MainActor in await perform(announcing: version, environment: environment) }
        running = task
        progress = .downloading(received: 0, total: nil)
        let reply = await task.value
        running = nil
        progress = .idle
        return reply
    }

    /// Ends the running Update with nothing changed, once its staging folder is gone: `ok`; or
    /// `error <reason>` when none runs, or the swap has begun and nothing can stop it any more.
    static func cancel() async -> String {
        guard let running else { return "error no Update is running" }
        guard progress.canCancel else { return "error the Update is swapping in the new copy" }
        running.cancel()
        _ = await running.value
        return "ok"
    }

    private static func perform(announcing version: String, environment: any InstallEnvironment) async -> String {
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
        if error is CancellationError { return "error \(Failure.cancelled.code) \(Failure.cancelled)" }
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
            try Task.checkCancellation()
            try await Task.detached { try extractApp(from: image, to: staged, in: staging) }.value
            // The detached work does not see a cancel, so it is looked at again here, and this is the
            // last place a cancel counts: nothing awaits between this check and `swapping`.
            try Task.checkCancellation()
            progress = .swapping
            cancelWorkInProgress()
            await environment.waitBeforeSwap()
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
            let status = try await endpoint.download(imageRequest, to: image) { received, total in
                Task { @MainActor in noteDownload(received: received, total: total) }
            }
            guard status == 200 else { throw Failure.status(status) }
        } catch let error as ReleaseEndpointError {
            throw Failure.network(error)
        }
        progress = .checking
        let actual = try await Task.detached { try DiskImage.sha256(of: image) }.value
        guard actual == published else { throw Failure.hashMismatch }
    }

    /// Bytes of the disk image that have arrived. A late report of a smaller number is ignored.
    private static func noteDownload(received: Int64, total: Int64?) {
        guard case .downloading(let had, _) = progress, received >= had else { return }
        progress = .downloading(received: received, total: total)
    }

    /// What snapit has under way stops when the swap begins, so nothing starts in an app that is
    /// about to quit: a Timed Capture that is counting down ends without taking a Capture.
    private static func cancelWorkInProgress() {
        AreaCaptureFlow.cancelTimedCapture()
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
