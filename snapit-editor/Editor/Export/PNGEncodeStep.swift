import Foundation

/// The last step of the Export pipeline: the engine encodes the pixels as a PNG that carries the
/// physical size and the display's color profile.
nonisolated enum PNGEncodeStep {
    static let id = "png"

    static func encode(_ image: ExportImage, level: PNGLevel) throws -> Data {
        try image.pixels.encodePNG(level: level, dpi: image.dpi)
    }
}
