import Foundation

/// The size and resolution a PNG Export is written at. One rule for every process and every
/// sink (Copy, Save, drag-out): "Export at standard resolution (1x)" averages a Retina image
/// down to its size in points and records 72 dpi; otherwise the pixels stay native and the PNG
/// records the Capture's own resolution (144 dpi on Retina).
nonisolated struct PNGOutputPlan: Equatable, Sendable {
    let width: Int
    let height: Int
    let dpi: Int
    /// True when the engine averages the image down while it encodes.
    let isDownscaled: Bool

    /// - Parameters:
    ///   - pixelWidth: the flattened image's width in pixels.
    ///   - scale: pixels per point.
    ///   - dpi: the resolution the image records at its own size.
    ///   - standardResolution: "Export at standard resolution (1x)".
    init(pixelWidth: Int, pixelHeight: Int, scale: Double, dpi: Int, standardResolution: Bool) {
        guard standardResolution, scale > 1 else {
            (width, height, self.dpi, isDownscaled) = (pixelWidth, pixelHeight, dpi, false)
            return
        }
        width = min(pixelWidth, max(1, Int((Double(pixelWidth) / scale).rounded())))
        height = min(pixelHeight, max(1, Int((Double(pixelHeight) / scale).rounded())))
        self.dpi = max(1, Int((Double(dpi) / scale).rounded()))
        isDownscaled = (width, height) != (pixelWidth, pixelHeight)
    }

    /// The resolution a Capture of this scale records at its own size: 72 dpi per pixel per point.
    static func nativeDPI(scale: Double) -> Int { Int((72 * scale).rounded()) }
}
