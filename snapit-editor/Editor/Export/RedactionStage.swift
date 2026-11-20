/// Pixelates every Redaction in the engine, in the Export's owned buffer, destroying the pixels
/// under it. The document has no Redaction yet, so the image passes through unchanged.
nonisolated struct RedactionStage: ExportStage {
    let id = "redaction"
    let order = 200

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        image
    }
}
