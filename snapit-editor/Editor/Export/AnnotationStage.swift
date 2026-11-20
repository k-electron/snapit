/// Draws the Annotations with Core Graphics straight onto the Export's owned buffer, shifted by
/// the image's `origin` after a crop. The document has no Annotation yet, so the image passes
/// through unchanged.
nonisolated struct AnnotationStage: ExportStage {
    let id = "annotations"
    let order = 300

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        image
    }
}
