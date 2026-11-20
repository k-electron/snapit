import Foundation

/// The PNG a drag out of the Editor offers: Fast-encoded (with the 1x downscale when that
/// setting is on) into a file in the private cache, named like the Saved file
/// (`snapit-YYYYMMDD-HHMMSS.png`, from the Capture's time). Finder, or whichever app takes the
/// drop, copies the file.
///
/// The encode starts when the mouse goes down on the thumbnail and runs in the background, so by
/// the time the pointer has moved far enough to start the drag the file is usually there.
nonisolated final class PendingDragFile: @unchecked Sendable {
    let url: URL
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var outcome: Result<URL, Error>?

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
        lock.withLock { outcome = result }
        done.signal()
    }

    /// Waits for the encode (blocking the caller) and returns the file, or throws what failed.
    /// Safe to call more than once.
    func wait() throws -> URL {
        done.wait()
        done.signal()
        return try lock.withLock { try outcome!.get() }
    }
}
