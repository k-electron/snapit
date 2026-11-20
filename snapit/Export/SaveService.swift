import AppKit
import Darwin
import Foundation

/// Save, in the menu bar app: it takes a flattened image the Editor helper left in a shared export
/// file, writes it into the Save location as `snapit-YYYYMMDD-HHMMSS.png` and finishes even if the
/// helper has quit by then.
///
/// `begin` is the quick part, answered to the helper at once:
///
/// 1. map the export file (read-only), then unlink it, so nothing of the Save is left in the cache
///    folder and the mapping is all that is needed from here on;
/// 2. create the hidden partial file in the Save location. That is the writability check, made by
///    really writing there (a folder macOS protects shows its prompt here, and a refusal comes back
///    as `SaveReply.folderNotWritable`, which keeps the Editor open).
///
/// The slow part runs on one serial queue, so Saves never encode two at a time and clashes get
/// their `-2`, `-3` in the order the Saves came in: Balanced-encode into the partial file (streamed,
/// the PNG is never in memory), then rename it to the first free name. The mapping and the
/// descriptor are gone when it ends, so memory returns to where it was.
///
/// A Save counts as pending from the moment `begin` starts (so a Quit during a folder prompt waits
/// too) until its file is written or it failed. Quitting waits for pending Saves
/// (`waitForSavesBeforeQuit`).
///
/// A failure after the hand-over (disk full, the rename failed) cannot reach the Editor, which may
/// be gone. It goes to the observers registered with `observeWriteFailures`, on the main queue
/// (`SaveFailureNotice` asks the Editor helper for a window); with none registered the menu bar app
/// beeps.
nonisolated final class SaveService: @unchecked Sendable {
    static let shared = SaveService()

    private let queue = DispatchQueue(label: "snapit.save", qos: .utility)
    private let lock = NSLock()
    private var pending = 0
    private var idleWaiters: [@Sendable () -> Void] = []
    private var inFlightPartials: Set<String> = []
    private var writeFailureObservers: [@Sendable (SaveWriteFailure) -> Void] = []
    private var checkFailureForTest: Int32?
    private var writeFailureForTest: Int32?
    private var heldForTest = false
    private var testDelay: TimeInterval = 0
    private let testGate = DispatchSemaphore(value: 0)

    /// How many Saves are still being written (or checked).
    var pendingCount: Int { lock.withLock { pending } }

    /// One locked step for Quit: true when a Save is pending, in which case `done` is called (on
    /// whichever thread finishes the last Save) once none is; false when none is, and `done` is
    /// never called.
    func waitForSavesBeforeQuit(_ done: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            guard pending > 0 else { return false }
            idleWaiters.append(done)
            return true
        }
    }

    /// Calls `observer`, on the main queue, when a Save fails after it was handed over (the Editor
    /// can no longer be told).
    func observeWriteFailures(_ observer: @escaping @Sendable (SaveWriteFailure) -> Void) {
        lock.withLock { writeFailureObservers.append(observer) }
    }

    // MARK: The request

    /// Checks the Save location (`folder`, read from `SaveLocation.folder` on the main actor) and
    /// queues the write. Call it off the main thread: a folder prompt blocks the calling thread
    /// until the user answers.
    func begin(exportPath: String, downscale: Bool, folder: URL) -> SaveReply {
        lock.withLock { pending += 1 }
        let reply = check(exportPath: exportPath, downscale: downscale, folder: folder)
        if reply != .accepted { finishOne() }
        return reply
    }

    private func check(exportPath: String, downscale: Bool, folder: URL) -> SaveReply {
        guard ExportFiles.isExportFile(path: exportPath) else { return .failed("not a shared export file") }
        let url = URL(fileURLWithPath: exportPath)
        let capture: OpenedCapture
        do {
            capture = try CaptureFiles.open(at: url)
        } catch {
            unlink(exportPath)
            return .failed("the export file could not be read: \(error)")
        }
        unlink(exportPath)  // the mapping keeps the pages; nothing is left to clean up

        let partialName = ".snapit-\(UUID().uuidString).partial"
        let partial = folder.appendingPathComponent(partialName)
        let descriptor: Int32
        if let injected = lock.withLock({ checkFailureForTest }) {
            // Test mode: the failure macOS's privacy check gives (EPERM) or a read-only volume's (EROFS),
            // which a run can't make for real.
            errno = injected
            descriptor = -1
        } else {
            descriptor = Darwin.open(partial.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        }
        guard descriptor >= 0 else { return .folderNotWritable(folder: folder.path, code: errno) }
        lock.withLock { _ = inFlightPartials.insert(partialName) }
        removeAbandonedPartials(in: folder)

        queue.async { [self] in
            write(capture, downscale: downscale, descriptor: descriptor, partial: partial, folder: folder)
            lock.withLock { _ = inFlightPartials.remove(partialName) }
            finishOne()
        }
        return .accepted
    }

    /// Removes hidden partial files an earlier run left behind (a crash, a force-quit mid-Save):
    /// exactly `.snapit-<UUID>.partial`, and none of the ones being written now.
    private func removeAbandonedPartials(in folder: URL) {
        let inFlight = lock.withLock { inFlightPartials }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where Self.isPartialName(name) && !inFlight.contains(name) {
            unlink(folder.appendingPathComponent(name).path)
        }
    }

    static func isPartialName(_ name: String) -> Bool {
        let prefix = ".snapit-", suffix = ".partial"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        return UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(suffix.count))) != nil
    }

    // MARK: The write

    private func write(_ capture: OpenedCapture, downscale: Bool, descriptor: Int32, partial: URL, folder: URL) {
        awaitTestGate()
        let info = capture.info
        let injectedFailure = lock.withLock { writeFailureForTest }
        let plan = PNGOutputPlan(
            pixelWidth: info.width, pixelHeight: info.height, scale: info.scale,
            dpi: PNGOutputPlan.nativeDPI(scale: info.scale), standardResolution: downscale)
        do {
            if let injectedFailure { throw EngineError(status: .ioFailed, rawValue: injectedFailure) }
            try capture.pixels.writePNG(level: .balanced, plan: plan, toDescriptor: descriptor)
            guard close(descriptor) == 0 else { throw EngineError(status: .ioFailed, rawValue: errno) }
        } catch {
            close(descriptor)
            unlink(partial.path)
            reportWriteFailure(error, folder: folder)
            return
        }
        do {
            let name = try claimName(for: partial, captureTime: info.captureTime, in: folder)
            NSLog("snapit: Saved \(name)")
        } catch {
            unlink(partial.path)
            reportWriteFailure(error, folder: folder)
        }
    }

    private func reportWriteFailure(_ error: Error, folder: URL) {
        let failure = SaveWriteFailure(folder: folder.path, code: (error as? EngineError)?.rawValue, message: "\(error)")
        NSLog("snapit: Save failed: \(failure.message)")
        let observers = lock.withLock { writeFailureObservers }
        DispatchQueue.main.async {
            if observers.isEmpty {
                if !TestMode.isActive { NSSound.beep() }
            } else {
                for observer in observers { observer(failure) }
            }
        }
    }

    /// Renames the finished partial file to the first free `snapit-YYYYMMDD-HHMMSS[-N].png`. The
    /// rename refuses to replace anything, so a name taken by another file is never overwritten.
    private func claimName(for partial: URL, captureTime: Date, in folder: URL) throws -> String {
        for attempt in 1...10_000 {
            let name = ExportFileName.fileName(captureTime: captureTime, attempt: attempt)
            let target = folder.appendingPathComponent(name)
            if renamex_np(partial.path, target.path, UInt32(RENAME_EXCL)) == 0 { return name }
            switch errno {
            case EEXIST:
                continue
            case ENOTSUP, ENOSYS, EINVAL:
                // A volume without exclusive rename: check, then rename.
                var status = stat()
                if lstat(target.path, &status) == 0 { continue }
                if rename(partial.path, target.path) == 0 { return name }
                throw EngineError(status: .ioFailed, rawValue: errno)
            default:
                throw EngineError(status: .ioFailed, rawValue: errno)
            }
        }
        throw EngineError(status: .ioFailed, rawValue: EEXIST)
    }

    private func finishOne() {
        let waiters: [@Sendable () -> Void] = lock.withLock {
            pending -= 1
            guard pending == 0 else { return [] }
            let all = idleWaiters
            idleWaiters = []
            return all
        }
        for waiter in waiters { waiter() }
    }

    // MARK: Test mode

    /// Holds every queued write until `releaseForTest()` (test mode only). The scripted run uses it
    /// to make the helper quit while a Save is still being written. The write thread sleeps on a
    /// semaphore: nothing polls.
    func holdForTest() {
        lock.withLock { heldForTest = true }
        while testGate.wait(timeout: .now()) == .success {}  // a release nobody was waiting for
    }

    func releaseForTest() {
        let wasHeld = lock.withLock {
            defer { heldForTest = false }
            return heldForTest
        }
        if wasHeld { testGate.signal() }
    }

    /// Makes every write start `seconds` late (test mode only). Unlike the hold it needs no command
    /// to let go of it, so Quit can be tested with a Save in progress: the write thread just sleeps.
    func delayWritesForTest(seconds: TimeInterval) {
        lock.withLock { testDelay = seconds }
    }

    /// Makes the writability check fail with `code` (an `errno`; nil to stop), as macOS's privacy
    /// check does for a folder the user denied (test mode only: a run never meets a real prompt).
    func failChecksForTest(code: Int32?) {
        lock.withLock { checkFailureForTest = code }
    }

    /// Makes every write fail with `code` once it starts (an `errno`; nil to stop): a disk that
    /// filled up after the hand-over. Test mode only.
    func failWritesForTest(code: Int32?) {
        lock.withLock { writeFailureForTest = code }
    }

    private func awaitTestGate() {
        guard TestMode.isActive else { return }
        let delay = lock.withLock { testDelay }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        guard lock.withLock({ heldForTest }) else { return }
        testGate.wait()
    }
}

/// A Save that failed after it was handed over: where it was going, the `errno` when the failure
/// has one, and the error's own words for the log.
nonisolated struct SaveWriteFailure: Sendable, Equatable {
    let folder: String
    let code: Int32?
    let message: String
}
