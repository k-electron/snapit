import CoreGraphics

/// Draws the Annotations with Core Graphics straight onto the Export's owned buffer, in the order
/// they are in the document, shifted by the image's `origin` after a crop. A kind that another
/// stage draws (`drawnByAnnotationStage` false) is skipped. With nothing to draw the image
/// passes through unchanged, so an Export with no Annotation never copies the Capture.
nonisolated struct AnnotationStage: ExportStage {
    let id = "annotations"
    let order = 300

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        let drawn = job.annotations.compactMap { annotation -> (Annotation, any AnnotationKind)? in
            guard let kind = AnnotationKinds.kind(annotation.kind), kind.drawnByAnnotationStage else { return nil }
            return (annotation, kind)
        }
        guard !drawn.isEmpty else { return image }

        var image = image
        try image.makeOwned()
        let pixels = image.pixels
        let height = CGFloat(pixels.height)
        let origin = image.origin
        let scale = CGFloat(image.scale)
        try pixels.withCGContext { context in
            // Image points, top left origin, onto the pixels of the (possibly cropped) buffer.
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -origin.x, y: -origin.y)
            context.scaleBy(x: scale, y: scale)
            for (annotation, kind) in drawn { kind.draw(annotation, in: context) }
        }
        return image
    }
}
