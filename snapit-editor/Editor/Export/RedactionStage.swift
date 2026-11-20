import Foundation

/// Pixelates every Redaction in the engine, into the Export's own buffer, so the pixels beneath
/// it are overwritten and gone from the Export for good. It runs after crop and before the
/// Annotations, so an Annotation drawn over a Redaction is drawn over the blocks.
///
/// Each Redaction pixelates the **original** pixels of the Capture (its read-only mapping, which
/// the job still holds), never what an earlier Redaction left in the buffer, and the Redactions
/// land in document order. That is what the canvas shows, one layer per Redaction on the Capture,
/// so Redactions that overlap look the same in the Export. With no Redaction the image passes
/// through unchanged.
nonisolated struct RedactionStage: ExportStage {
    let id = "redaction"
    let order = 200

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        let capture = job.image.pixels
        // What crop left of the Capture, in the Capture's pixels.
        let window = PixelRect(
            x: Int(image.origin.x), y: Int(image.origin.y), width: image.pixels.width, height: image.pixels.height)
        let geometries = job.annotations.filter { $0.kind == .redaction }.compactMap {
            RedactionGeometry(
                annotation: $0, scale: image.scale, captureWidth: capture.width, captureHeight: capture.height,
                window: window)
        }
        guard !geometries.isEmpty else { return image }

        var image = image
        try image.makeOwned()
        for geometry in geometries {
            try Engine.pixelate(
                capture, window: window, area: geometry.area, block: geometry.block, into: image.pixels,
                at: geometry.area.origin)
        }
        return image
    }
}
