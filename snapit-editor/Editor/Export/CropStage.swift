/// Cuts the image to the document's crop rectangle in the engine, into a buffer of its own. The
/// document has no crop yet, so the image passes through unchanged.
nonisolated struct CropStage: ExportStage {
    let id = "crop"
    let order = 100

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        image
    }
}
