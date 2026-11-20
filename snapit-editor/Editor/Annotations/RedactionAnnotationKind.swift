import CoreGraphics
import Foundation
import QuartzCore

nonisolated extension AnnotationKindID {
    static let redaction = AnnotationKindID("redaction")
}

/// Redaction: pixelates what lies beneath the box from `start` to `end` in bold blocks, and on
/// Export destroys those pixels (`RedactionStage`). `AnnotationStage` leaves it alone, so it lies
/// beneath every other Annotation, in the canvas, in hit testing and in the Export.
///
/// Its preview is not a drawing but the engine's own pixelate of the Capture's pixels
/// (`RedactionPreviewLayer`), the call the Export makes.
nonisolated struct RedactionAnnotationKind: AnnotationKind {
    let id = AnnotationKindID.redaction
    let drawnByAnnotationStage = false

    /// The box. It has a (clear) fill so a click anywhere inside picks it.
    func paint(for annotation: Annotation) -> AnnotationPaint {
        AnnotationPaint(path: CGPath(rect: annotation.box, transform: nil), fill: CGColor(gray: 0, alpha: 0))
    }

    @MainActor func makeLayer(in context: AnnotationRenderContext) -> CALayer { RedactionPreviewLayer() }

    @MainActor func update(_ layer: CALayer, for annotation: Annotation, in context: AnnotationRenderContext) {
        (layer as? RedactionPreviewLayer)?.show(annotation, in: context)
    }
}

/// The preview of one Redaction: a layer whose contents are the pixelated pixels, in a buffer of
/// exactly the Redaction's area, placed on the Capture's pixel grid. It renders again only when
/// the Redaction, the crop or the Capture changed, never for a zoom.
nonisolated final class RedactionPreviewLayer: CALayer {
    private struct Key: Equatable {
        let area: PixelRect
        let block: Int
        let window: PixelRect
        let scale: Double
        let capture: ObjectIdentifier
    }

    private var key: Key?

    override init() {
        super.init()
        // The effect layers' parent is flipped (image points, origin at the top left); flipping
        // this layer too keeps its contents upright.
        isGeometryFlipped = true
        contentsGravity = .resize
        minificationFilter = .trilinear
        magnificationFilter = .nearest
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("RedactionPreviewLayer is made in code") }

    @MainActor func show(_ annotation: Annotation, in context: AnnotationRenderContext) {
        guard let capture = context.capture else { return hide() }
        let window = context.cropPixels ?? PixelRect(x: 0, y: 0, width: capture.width, height: capture.height)
        guard
            let geometry = RedactionGeometry(
                annotation: annotation, scale: context.scale, captureWidth: capture.width,
                captureHeight: capture.height, window: window)
        else { return hide() }
        let key = Key(
            area: geometry.area, block: geometry.block, window: window, scale: context.scale,
            capture: ObjectIdentifier(capture))
        guard key != self.key else { return }
        do {
            let pixels = try capture.makeEmptyBuffer(width: geometry.area.width, height: geometry.area.height)
            try Engine.pixelate(capture, window: window, area: geometry.area, block: geometry.block, into: pixels)
            contents = pixels.makeCGImage()
        } catch {
            NSLog("snapit Editor: Redaction preview failed: \(error)")
            return hide()
        }
        let placed = geometry.area.offset(by: window.x, window.y)
        frame = CropGeometry.points(placed, scale: context.scale)
        isHidden = false
        self.key = key
    }

    @MainActor private func hide() {
        contents = nil
        isHidden = true
        key = nil
    }
}
