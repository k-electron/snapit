import CoreGraphics

/// Where a Redaction lands in pixels and how bold its blocks are. The live preview and the
/// Export both ask here, so they pixelate the same rectangle with the same blocks.
///
/// The Redaction's box (image points) snaps to whole device pixels of the Capture, each edge to
/// the nearest one. The blocks are a third of the box's short side, between 14 and 48 points and
/// never under 4 pixels, so a small Redaction is a few big squares and a large one is still
/// unmistakable. The pixelate happens on the image that is shown or exported, which is the Capture
/// or the part of it a crop kept (`window`): the part of the box outside it is dropped, and the
/// grid of blocks starts at the corner of what is left.
nonisolated struct RedactionGeometry: Equatable, Sendable {
    /// The rectangle to pixelate, in the pixels of the window.
    let area: PixelRect
    /// The side of a block, in pixels.
    let block: Int

    static let smallestBlock: CGFloat = 14
    static let largestBlock: CGFloat = 48
    static let fewestPixels = 4

    /// Nil when nothing of the Redaction is inside the window.
    /// - Parameters:
    ///   - scale: pixels per point of the Capture.
    ///   - captureWidth: the Capture's width in pixels (and `captureHeight`).
    ///   - window: the part of the Capture that is shown or exported, in Capture pixels.
    init?(annotation: Annotation, scale: Double, captureWidth: Int, captureHeight: Int, window: PixelRect) {
        guard
            let box = CropGeometry.pixelRect(annotation.box, scale: scale, width: captureWidth, height: captureHeight)
        else { return nil }
        let shortSide = CGFloat(min(box.width, box.height)) / CGFloat(scale)
        let points = min(max(shortSide / 3, Self.smallestBlock), Self.largestBlock)
        block = max(Self.fewestPixels, Int((points * CGFloat(scale)).rounded()))

        let x0 = max(box.x, window.x), y0 = max(box.y, window.y)
        let x1 = min(box.x + box.width, window.x + window.width), y1 = min(box.y + box.height, window.y + window.height)
        guard x1 > x0, y1 > y0 else { return nil }
        area = PixelRect(x: x0 - window.x, y: y0 - window.y, width: x1 - x0, height: y1 - y0)
    }
}
