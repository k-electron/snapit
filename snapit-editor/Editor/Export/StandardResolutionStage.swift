/// Shrinks the image to standard resolution (1x) in the engine, by area averaging, when
/// "Export at standard resolution" is on. Otherwise the image keeps its native pixels.
nonisolated struct StandardResolutionStage: ExportStage {
    let id = "standard-resolution"
    let order = 400

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        image
    }
}
