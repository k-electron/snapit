import CoreGraphics
import Foundation

/// The image as it travels down the Export pipeline: pixels in engine memory, how many pixels
/// make a point, and the resolution the PNG will record. The display's ICC profile rides on
/// `pixels` and is embedded in the PNG byte for byte; every buffer a stage makes with
/// `pixels.makeEmptyBuffer(width:height:)` or `makeOwnedCopy()` carries it along.
nonisolated struct ExportImage: Sendable {
    /// At the start of the pipeline, the Capture's read-only mapping. Never write to it.
    var pixels: PixelBuffer
    /// Pixels per point.
    var scale: Double
    /// Dots per inch recorded in the PNG.
    var dpi: Int
    /// Where this image's top-left pixel sat in the Capture. Crop moves it, so Annotations
    /// (stored in the Capture's own coordinates) are drawn shifted by it.
    var origin = CGPoint.zero
    /// Set by the 1x step for the encode step to read: standard resolution is made in the same
    /// pass as the PNG encode, never in a buffer of its own.
    var downscaleOnEncode = false

    /// True once `pixels` is a buffer of the Export's own that stages may change in place.
    var isOwned: Bool { pixels.isWritable }

    /// Makes `pixels` the Export's own writable buffer: one copy if it is still the Capture's
    /// mapping, nothing if an earlier stage already did.
    mutating func makeOwned() throws {
        if !isOwned { pixels = try pixels.makeOwnedCopy() }
    }
}

/// Everything an Export needs, taken from the Editor's document on the main actor so the
/// pipeline can run on any thread. A feature that adds document state a stage reads (the crop,
/// the Annotations) adds a field here in its own change and fills it in
/// `EditorDocument.makeExportJob()`.
nonisolated struct ExportJob: Sendable {
    let image: ExportImage
    let level: PNGLevel
    /// "Export at standard resolution" (1x) was on when the Export started.
    let standardResolution: Bool
}

/// One step of the Export pipeline.
///
/// **A stage never touches the Capture's mapping.** The first stage that changes pixels makes
/// the Export's one owned buffer: crop returns a smaller buffer from `makeEmptyBuffer`, and a
/// stage that changes pixels in place calls `image.makeOwned()` first. Later stages (Redaction,
/// Annotations) then find `image.isOwned` and change that buffer in place, with no copy of their
/// own. A stage with nothing to do returns its input untouched, so an Export with no crop,
/// Redaction or Annotation never copies the Capture.
///
/// A feature adds a file with its stage and one line in `ExportPipeline.stages`; position comes
/// from `order`. The orders are spaced out: crop 100, Redaction 200, Annotations 300, 1x 400.
nonisolated protocol ExportStage: Sendable {
    /// Stable name.
    var id: String { get }
    var order: Int { get }
    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage
}
