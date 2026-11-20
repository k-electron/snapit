import CoreGraphics

/// Cuts the image to the document's crop rectangle in the engine, into a buffer of its own, and
/// records where the cut sits in the Capture (`ExportImage.origin`, in pixels) so Redactions and
/// Annotations, which are stored in the Capture's own coordinates, land in the right place. The
/// rectangle is in points; `CropGeometry.pixelRect` snaps it to device pixels, as the canvas does.
/// With no crop, or one that keeps everything, the image passes through unchanged.
nonisolated struct CropStage: ExportStage {
    let id = "crop"
    let order = 100

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        guard let crop = job.crop,
            let area = CropGeometry.pixelRect(
                crop, scale: image.scale, width: image.pixels.width, height: image.pixels.height),
            area != PixelRect(x: 0, y: 0, width: image.pixels.width, height: image.pixels.height)
        else { return image }
        let cut = try image.pixels.makeEmptyBuffer(width: area.width, height: area.height)
        try Engine.crop(image.pixels, to: area, into: cut)
        var image = image
        image.pixels = cut
        image.origin = CGPoint(x: image.origin.x + Double(area.x), y: image.origin.y + Double(area.y))
        return image
    }
}
