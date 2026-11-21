import CoreGraphics

/// The Export drawn directly at thumbnail size, for the drag-out thumbnail: the crop applied, every
/// Redaction pixelated and every Annotation drawn, from the document as it is now. The engine
/// averages the kept part of the Capture down first (reading a few rows for each row of the
/// result, so most of a big Capture's pages are never touched), and the Redactions and
/// Annotations are then made on that small buffer. No full-size image is made.
///
/// It is the Export's own stages at the thumbnail's scale: the crop rectangle is `CropStage`'s,
/// the Redaction rectangles and blocks are `RedactionGeometry`'s (then scaled down with the
/// Capture), and the Annotations are `AnnotationStage` itself. A Redaction's blocks are a fraction
/// of a thumbnail pixel on a big Capture, so there it shows as the average of what it covers,
/// which is what the Export's pixelated blocks average to.
nonisolated enum ExportThumbnail {
    /// The thumbnail of `job`'s Export: neither side longer than `maxSide` pixels.
    static func render(_ job: ExportJob, maxSide: Int) throws -> PixelBuffer {
        let capture = job.image.pixels
        let scale = job.image.scale
        let window =
            job.crop.flatMap {
                CropGeometry.pixelRect($0, scale: scale, width: capture.width, height: capture.height)
            } ?? PixelRect(x: 0, y: 0, width: capture.width, height: capture.height)
        let thumbnail = try capture.makeThumbnail(maxSide: maxSide, window: window)
        // Thumbnail pixels for each pixel of the Capture, taken from the longer side so the
        // rounding of the shorter one never shows.
        let factor = Double(max(thumbnail.width, thumbnail.height)) / Double(max(window.width, window.height))

        var image = ExportImage(
            pixels: thumbnail, scale: scale * factor, dpi: job.image.dpi,
            origin: CGPoint(x: Double(window.x) * factor, y: Double(window.y) * factor))
        let geometries = job.annotations.filter { $0.kind == .redaction }.compactMap {
            RedactionGeometry(
                annotation: $0, scale: scale, captureWidth: capture.width, captureHeight: capture.height,
                window: window)
        }
        if !geometries.isEmpty {
            let source = thumbnail
            image.pixels = try source.makeOwnedCopy()
            let whole = PixelRect(x: 0, y: 0, width: source.width, height: source.height)
            for geometry in geometries {
                let area = Self.scaled(geometry.area, by: factor, within: whole)
                let block = max(1, Int((Double(geometry.block) * factor).rounded()))
                try Engine.pixelate(
                    source, window: whole, area: area, block: block, into: image.pixels, at: area.origin)
            }
        }
        return try AnnotationStage().apply(to: image, job: job).pixels
    }

    /// `area` (in the Capture's pixels) in thumbnail pixels: each edge to the nearest one, at least one
    /// pixel wide and high, inside `bounds`.
    private static func scaled(_ area: PixelRect, by factor: Double, within bounds: PixelRect) -> PixelRect {
        func edges(_ start: Int, _ length: Int, limit: Int) -> (Int, Int) {
            let low = min(Int((Double(start) * factor).rounded()), limit - 1)
            let high = min(max(Int((Double(start + length) * factor).rounded()), low + 1), limit)
            return (low, high - low)
        }
        let (x, width) = edges(area.x, area.width, limit: bounds.width)
        let (y, height) = edges(area.y, area.height, limit: bounds.height)
        return PixelRect(x: x, y: y, width: width, height: height)
    }
}
