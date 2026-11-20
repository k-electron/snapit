import Foundation

/// The flattened image, written into a file the menu bar app encodes from.
nonisolated struct SharedExport: Sendable {
    /// The shared export file (Capture file format, in the cache's `exports/` folder).
    let url: URL
    /// The engine averages the image down to 1x when it encodes ("Export at standard resolution").
    let downscale: Bool
}

/// The places a flattened image can go besides the pasteboard (`ExportPipeline.run` is Copy).
nonisolated extension ExportPipeline {
    /// Save: flattens the job and writes the result into a new shared export file, a memory-mapped
    /// file in the Capture file format that carries the Capture's scale, time and color profile.
    /// The menu bar app maps it, Balanced-encodes it in the background and writes the Saved file.
    /// The 1x downscale is not made here: it travels as a flag and the engine does it in the
    /// encode pass. Everything of the image in this process is freed before this returns.
    @concurrent
    static func flattenIntoSharedFile(_ job: ExportJob, captureTime: Date) async throws -> SharedExport {
        let image = try flatten(job)
        try ExportFiles.ensureFolder(ExportFiles.exportsFolder)
        let url = ExportFiles.exportsFolder.appendingPathComponent("export-\(UUID().uuidString).pixels")
        let source = image.pixels
        do {
            let profile = source.iccProfile ?? (source.colorSpace.copyICCData() as Data?) ?? Data()
            let file = try CaptureFiles.create(
                at: url, width: source.width, height: source.height, scale: image.scale, captureTime: captureTime,
                icc: profile, colorSpace: source.colorSpace)
            let rowBytes = source.width * 4
            let rows = source.height
            source.withReadOnlyPixels { from, fromStride in
                file.withPixels { to, toStride in
                    for row in 0..<rows { memcpy(to + row * toStride, from + row * fromStride, rowBytes) }
                }
            }
        } catch {
            unlink(url.path)
            throw error
        }
        return SharedExport(url: url, downscale: image.downscaleOnEncode)
    }

    /// Drag-out: flattens the job and Fast-encodes it, streamed, into the file at `url`.
    @concurrent
    static func writePNG(_ job: ExportJob, to url: URL) async throws {
        try PNGEncodeStep.write(flatten(job), level: job.level, to: url)
    }
}
