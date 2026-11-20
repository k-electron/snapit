import Foundation

/// The image as it travels down the Export pipeline: pixels in engine memory, how many pixels
/// make a point, and the resolution the PNG will record. The display's ICC profile rides on
/// `pixels` and is embedded in the PNG byte for byte.
nonisolated struct ExportImage: Sendable {
    var pixels: PixelBuffer
    /// Pixels per point.
    var scale: Double
    /// Dots per inch recorded in the PNG.
    var dpi: Int
}

/// Everything an Export needs, taken from the Editor's document on the main actor so the
/// pipeline can run on any thread. A feature that adds document state a stage reads (the crop,
/// the Annotations) adds a field here in its own change and fills it in
/// `EditorDocument.makeExportJob()`.
nonisolated struct ExportJob: Sendable {
    let image: ExportImage
    let level: PNGLevel
}

/// One step of the Export pipeline. Never modifies its input's pixels: a stage that changes
/// them returns a new buffer, so the Capture (a read-only mapping) stays exactly as taken.
///
/// A feature adds a file with its stage and one line in `ExportPipeline.stages`; position comes
/// from `order`. The orders are spaced out: crop 100, Redaction 200, Annotations 300, 1x 400.
nonisolated protocol ExportStage: Sendable {
    /// Stable name.
    var id: String { get }
    var order: Int { get }
    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage
}
