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
nonisolated final class SaveService: @unchecked Sendable {
    static let shared = SaveService()

    private let queue = DispatchQueue(label: "snapit.save", qos: .utility)
    private let lock = NSLock()
    private var pending = 0
    private var idleWaiters: [@Sendable () -> Void] = []
    private var heldForTest = false
    private let testGate = DispatchSemaphore(value: 0)

    /// How many Saves are still being written.
    var pendingCount: Int { lock.withLock { pending } }

    /// Calls `body` once no Save is being written (at once when none is).
    func whenIdle(_ body: @escaping @Sendable () -> Void) {
        let runNow: Bool = lock.withLock {
            if pending == 0 { return true }
            idleWaiters.append(body)
            return false
        }
        if runNow { body() }
    }

    // MARK: The request

    /// Checks the Save location (`folder`, read from `SaveLocation.folder` on the main actor) and queues the write. Call it off the main thread: a folder
    /// prompt blocks the calling thread until the user answers.
    func begin(exportPath: String, downscale: Bool, folder: URL) -> SaveReply {
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

        let partial = folder.appendingPathComponent(".snapit-\(UUID().uuidString).partial")
        let descriptor = Darwin.open(partial.path, O_WRONLY | O_CREAT | O_EXCL, 0o666)
        guard descriptor >= 0 else { return .folderNotWritable(folder: folder.path, code: errno) }

        lock.withLock { pending += 1 }
        queue.async { [self] in
            write(capture, downscale: downscale, descriptor: descriptor, partial: partial, folder: folder)
            finishOne()
        }
        return .accepted
    }

    // MARK: The write

    private func write(_ capture: OpenedCapture, downscale: Bool, descriptor: Int32, partial: URL, folder: URL) {
        awaitTestGate()
        let info = capture.info
        let plan = PNGOutputPlan(
            pixelWidth: info.width, pixelHeight: info.height, scale: info.scale,
            dpi: PNGOutputPlan.nativeDPI(scale: info.scale), standardResolution: downscale)
        do {
            try capture.pixels.writePNG(level: .balanced, plan: plan, toDescriptor: descriptor)
            guard close(descriptor) == 0 else { throw EngineError(status: .ioFailed, rawValue: errno) }
        } catch {
            close(descriptor)
            unlink(partial.path)
            NSLog("snapit: Save failed: \(error)")
            if !TestMode.isActive { DispatchQueue.main.async { NSSound.beep() } }
            return
        }
        do {
            let name = try claimName(for: partial, captureTime: info.captureTime, in: folder)
            NSLog("snapit: Saved \(name)")
        } catch {
            unlink(partial.path)
            NSLog("snapit: Save failed: \(error)")
            if !TestMode.isActive { DispatchQueue.main.async { NSSound.beep() } }
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

    private func awaitTestGate() {
        guard TestMode.isActive, lock.withLock({ heldForTest }) else { return }
        testGate.wait()
    }
}
