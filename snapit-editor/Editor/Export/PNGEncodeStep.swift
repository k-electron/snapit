import Foundation

/// The last step of the Export pipeline: the engine encodes the pixels as a PNG that carries the
/// physical size and the display's color profile. When the image's `downscaleOnEncode` is set
/// ("Export at standard resolution (1x)") the engine averages the pixels down in this same
/// pass, and the PNG records 72 dpi.
nonisolated enum PNGEncodeStep {
    static let id = "png"

    static func encode(_ image: ExportImage, level: PNGLevel) throws -> Data {
        try image.pixels.encodePNG(level: level, plan: plan(for: image))
    }

    /// Streams the PNG into a new file at `url`, never holding it in memory.
    static func write(_ image: ExportImage, level: PNGLevel, to url: URL) throws {
        try image.pixels.writePNG(level: level, plan: plan(for: image), to: url)
    }

    /// The size and resolution the PNG of `image` is written at.
    static func plan(for image: ExportImage) -> PNGOutputPlan {
        PNGOutputPlan(
            pixelWidth: image.pixels.width, pixelHeight: image.pixels.height, scale: image.scale, dpi: image.dpi,
            standardResolution: image.downscaleOnEncode)
    }
}
