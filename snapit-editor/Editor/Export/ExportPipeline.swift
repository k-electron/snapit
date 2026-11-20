import Foundation

/// Export: crop, then Redactions (pixelated in the engine), then Annotations (Core Graphics),
/// then the optional 1x downscale, then PNG. Flattening happens only here, never while the
/// user edits. Copy, Save and drag-out run the same pipeline and differ in the PNG level.
nonisolated enum ExportPipeline {
    /// Every stage before the PNG encode. A feature adds its stage with one line; the order of
    /// the lines never matters (each stage has its own `order`).
    static let stages: [any ExportStage] = {
        let all: [any ExportStage] = [
            CropStage(),
            RedactionStage(),
            AnnotationStage(),
            StandardResolutionStage(),
        ]
        return all.sorted { $0.order < $1.order }
    }()

    /// The names of the steps, in the order they run, ending with the PNG encode.
    static var stageIDs: [String] { stages.map(\.id) + [PNGEncodeStep.id] }

    /// Runs every stage over the job's image and encodes the result.
    static func run(_ job: ExportJob) throws -> Data {
        var image = job.image
        for stage in stages {
            image = try stage.apply(to: image, job: job)
        }
        return try PNGEncodeStep.encode(image, level: job.level)
    }

    /// The same, off the calling actor: an Export of a 5K Capture is tens of milliseconds and
    /// must never block the Editor's window.
    @concurrent
    static func runInBackground(_ job: ExportJob) async throws -> Data {
        try run(job)
    }
}
