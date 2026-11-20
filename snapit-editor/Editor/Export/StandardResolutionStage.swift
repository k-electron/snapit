/// Sets `downscaleOnEncode` from "Export at standard resolution" (1x). It makes no buffer: the
/// encode step averages the pixels down in the same pass as the PNG encode.
nonisolated struct StandardResolutionStage: ExportStage {
    let id = "standard-resolution"
    let order = 400

    func apply(to image: ExportImage, job: ExportJob) throws -> ExportImage {
        var image = image
        image.downscaleOnEncode = job.standardResolution
        return image
    }
}
