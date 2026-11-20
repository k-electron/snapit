import AppKit
import CoreGraphics
import QuartzCore

nonisolated extension AnnotationKindID {
    static let text = AnnotationKindID("text")
}

/// Text: what the user typed, from its top left corner at `start`, in the Annotation color at the
/// style's text size. Core Text draws it, in the preview and in the Export alike (`TextLayout`).
nonisolated struct TextAnnotationKind: AnnotationKind {
    let id = AnnotationKindID.text
    let widthChoice = WidthChoice.none
    let usesTextSize = true

    /// How far past the text a click still picks it, in image points.
    private static let reach: CGFloat = 4

    func paint(for annotation: Annotation) -> AnnotationPaint {
        AnnotationPaint(path: CGPath(rect: bounds(of: annotation), transform: nil))
    }

    func bounds(of annotation: Annotation) -> CGRect {
        let size = TextLayout(text: annotation.text, fontSize: annotation.style.textSize).size
        return CGRect(origin: annotation.start, size: size)
    }

    /// The text's box, a little roomier than the glyphs.
    func hit(_ annotation: Annotation, at point: CGPoint, minimumWidth: CGFloat) -> Bool {
        bounds(of: annotation).insetBy(dx: -Self.reach, dy: -Self.reach).contains(point)
    }

    /// A text is resized with its text size, never by a handle.
    func handles(of annotation: Annotation) -> [CGPoint] { [] }
    func moveHandle(_ index: Int, to point: CGPoint, in annotation: Annotation) -> Annotation { annotation }

    /// A text with nothing in it leaves nothing to see or click.
    func isLargeEnough(_ annotation: Annotation) -> Bool { !annotation.text.isEmpty }

    func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(annotation.style.color.cgColor)
        TextLayout(text: annotation.text, fontSize: annotation.style.textSize).draw(at: annotation.start, in: context)
    }

    @MainActor func makeLayer(in context: AnnotationRenderContext) -> CALayer { TextAnnotationLayer() }

    @MainActor func update(_ layer: CALayer, for annotation: Annotation, in context: AnnotationRenderContext) {
        (layer as? TextAnnotationLayer)?.show(annotation, kind: self, in: context)
    }
}

/// The canvas's layer for a Text: a layer that draws the same Core Text lines the Export does, a
/// little larger than the text so no glyph is clipped. It draws once per change (never while
/// idle), at the Capture's pixel density so it is as sharp as the Capture under it.
nonisolated final class TextAnnotationLayer: CALayer {
    private static let padding: CGFloat = 2
    private var annotation: Annotation?
    private var kind = TextAnnotationKind()
    /// Where the layer's top left is on the canvas, in image points (whole points, so the layer's
    /// pixels land on the canvas's pixels and nothing is resampled).
    private var origin = CGPoint.zero

    override init() {
        super.init()
        isOpaque = false
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("TextAnnotationLayer is made in code") }

    /// No implicit animations: the text is where the Annotation says it is.
    override func action(forKey event: String) -> CAAction? { NSNull() }

    @MainActor func show(_ annotation: Annotation, kind: TextAnnotationKind, in context: AnnotationRenderContext) {
        let box = kind.bounds(of: annotation).insetBy(dx: -Self.padding, dy: -Self.padding).integral
        // Backing pixels per layer point: the Capture's density, and more when it is shown scaled down.
        let density = min(8, max(context.scale, 1) / max(context.zoom, 0.05))
        if self.annotation != annotation || frame != box || contentsScale != density {
            self.annotation = annotation
            self.kind = kind
            origin = box.origin
            frame = box
            contentsScale = density
            setNeedsDisplay()
        }
    }

    override func draw(in context: CGContext) {
        guard let annotation else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // The layer's own space has its origin at the box's top left; the context may be y-up or y-down.
        if context.ctm.d > 0 {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.translateBy(x: -origin.x, y: -origin.y)
        kind.draw(annotation, in: context)
    }
}
