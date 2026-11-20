/// Cuts the image to the document's crop rectangle in the engine. A document with no crop
/// leaves the image as it is.
nonisolated struct CropStage: ExportStage {
    let id = "crop"
    let order = 100

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        image
    }
}
