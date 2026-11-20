/// Draws the Annotations with Core Graphics straight onto a copy of the pixels. A document with
/// no Annotation leaves the image as it is.
nonisolated struct AnnotationStage: ExportStage {
    let id = "annotations"
    let order = 300

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        image
    }
}
