import Foundation

nonisolated extension SocketCommand {
    /// `editor-export-timing <N>`: runs Editor N's Export (a Copy's: Fast encode) off the main actor
    /// without touching the pasteboard, and replies `flatten-ms=<n> encode-ms=<n>`: how long the
    /// pipeline's stages (crop, Redactions, Annotations) took, and the PNG encode. The scripted run
    /// bounds the pipeline's own time with it, which the end-to-end time of a Copy would hide.
    /// Test mode only.
    static let editorExportTiming = SocketCommand("editor-export-timing")
}

extension SocketCommandRegistry {
    func registerExportTimingTestCommands() {
        guard TestMode.isActive else { return }

        register(.editorExportTiming) { request in
            guard let number = request.arguments.first.flatMap(Int.init),
                let job = await EditorSessions.shared.session(captureNumber: number)?.document?.makeExportJob(level: .fast)
            else { return "error editor-export-timing <N>" }
            do {
                let (flatten, encode) = try await Self.timeExport(job)
                return "flatten-ms=\(flatten) encode-ms=\(encode)"
            } catch {
                return "error \(error)"
            }
        }
    }

    @concurrent
    private static func timeExport(_ job: ExportJob) async throws -> (flatten: Int, encode: Int) {
        let clock = ContinuousClock()
        var flattened: ExportImage?
        let flatten = try clock.measure { flattened = try ExportPipeline.flatten(job) }
        guard let flattened else { return (0, 0) }
        let encode = try clock.measure { _ = try PNGEncodeStep.encode(flattened, level: job.level) }
        func milliseconds(_ duration: Duration) -> Int {
            Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
        }
        return (milliseconds(flatten), milliseconds(encode))
    }
}
