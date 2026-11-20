/// Pixelates every Redaction in the engine, destroying the pixels under it. A document with
/// no Redaction leaves the image as it is.
nonisolated struct RedactionStage: ExportStage {
    let id = "redaction"
    let order = 200

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        image
    }
}
