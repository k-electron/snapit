import Foundation

/// Export: crop, then Redactions (pixelated in the engine), then Annotations (Core Graphics),
/// then the optional 1x downscale, then PNG. Flattening happens only here, never while the
/// user edits.
///
/// `flatten` runs the stages and returns the flattened image; a sink takes it from there. Copy
/// and drag-out Fast-encode it (`run`); Save writes it into a shared export file and sends a
/// Save request, so it flattens and stops.
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

    /// Runs every stage over the job's image.
    static func flatten(_ job: ExportJob) throws -> ExportImage {
        var image = job.image
        for stage in stages {
            image = try stage.apply(to: image, job: job)
        }
        return image
    }

    /// Flattens and encodes the result as a PNG.
    static func run(_ job: ExportJob) throws -> Data {
        try PNGEncodeStep.encode(flatten(job), level: job.level)
    }

    /// The same, off the calling actor: an Export of a 5K Capture is tens of milliseconds and
    /// must never block the Editor's window.
    @concurrent
    static func runInBackground(_ job: ExportJob) async throws -> Data {
        try run(job)
    }
}
