import Foundation

/// The PNG a drag out of the Editor offers: Fast-encoded (with the 1x downscale when that
/// setting is on) into a file in the private cache, named like the Saved file
/// (`snapit-YYYYMMDD-HHMMSS.png`, from the Capture's time). Finder, or whichever app takes the
/// drop, copies the file.
///
/// The encode starts when the mouse goes down on the thumbnail and runs in the background, so by
/// the time the pointer has moved far enough to start the drag the file is usually there; the drag
/// starts the moment it is (`notify`), and the main thread never waits for it. The file is written
/// next to its final name and renamed into place (`PixelBuffer.writePNG(to:)`), so an app that is
/// still reading an earlier drag's file is not disturbed.
nonisolated final class PendingDragFile: @unchecked Sendable {
    let url: URL
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var finished: Result<URL, Error>?
    private var callback: (@Sendable (Result<URL, Error>) -> Void)?

    /// Starts the Fast encode for `job`. `captureTime` gives the file its name.
    @MainActor
    init(job: ExportJob, captureNumber: Int, captureTime: Date) {
        let folder = ExportFiles.dragOutFolder(captureNumber: captureNumber)
        url = folder.appendingPathComponent(ExportFileName.fileName(captureTime: captureTime))
        let target = url
        Task.detached { [self] in
            do {
                try ExportFiles.ensureFolder(folder)
                try await ExportPipeline.writePNG(job, to: target)
                finish(.success(target))
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let waiting: (@Sendable (Result<URL, Error>) -> Void)? = lock.withLock {
            finished = result
            defer { callback = nil }
            return callback
        }
        done.signal()
        waiting?(result)
    }

    /// How the encode ended; nil while it is still running.
    var outcome: Result<URL, Error>? { lock.withLock { finished } }

    /// Calls `body` with the outcome, on whichever thread finishes the encode, or at once (on the
    /// caller's thread) when it has finished already.
    func notify(_ body: @escaping @Sendable (Result<URL, Error>) -> Void) {
        let ready: Result<URL, Error>? = lock.withLock {
            if finished == nil { callback = body }
            return finished
        }
        if let ready { body(ready) }
    }

    /// Waits for the encode (blocking the caller) and returns the file, or throws what failed.
    /// Safe to call more than once. For tests and callers that are not on the main thread.
    func wait() throws -> URL {
        done.wait()
        done.signal()
        return try lock.withLock { try finished!.get() }
    }
}
