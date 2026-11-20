import CoreGraphics
import QuartzCore

/// How an Annotation is painted: one description, used by the canvas's preview layer and by
/// the Export's Core Graphics drawing alike, so what the user sees is what Export draws.
/// Coordinates are image points, origin at the top left.
nonisolated struct AnnotationPaint {
    var path: CGPath
    /// Fills the path in this color; nil for no fill.
    var fill: CGColor?
    /// Strokes the path in this color; nil for no stroke.
    var stroke: CGColor?
    var lineWidth: CGFloat = 0
    var lineCap = CGLineCap.butt
    var lineJoin = CGLineJoin.miter
}

/// What a kind's preview layer can know about the Editor it is in: the Capture's pixels (the
/// read-only mapping: read them with `withReadOnlyPixels`, never write), how many pixels make a
/// point, and the canvas's zoom (view points per image point). A kind that previews from the
/// Capture (Redaction, through the engine, to match the Export) reads it here; a kind that
/// paints from its path ignores it.
@MainActor
struct AnnotationRenderContext {
    let capture: PixelBuffer?
    /// Pixels per point.
    let scale: Double
    let zoom: CGFloat
    /// The part of the Capture the canvas shows, in Capture pixels, when a crop is applied; nil
    /// for all of it. A kind that previews from the Capture works on this part, as Export does.
    var cropPixels: PixelRect?
    /// True while the pointer is dragging (an Annotation being drawn, moved or resized): a kind
    /// whose preview is costly may update at most every few milliseconds and catch up when the
    /// drag ends (`AnnotationLayers.settle`).
    var isLive = false
}

/// What one kind of Annotation does. A feature adds a file with its kind and one line in
/// `AnnotationKinds`; nothing else changes. A kind that is painted from a path only gives
/// `paint(for:)` and gets the preview layer, the exact hit test, the selection handles and the
/// Export drawing for free. A kind that needs more (Text) overrides what differs.
nonisolated protocol AnnotationKind: Sendable {
    /// Stable name, stored in documents.
    var id: AnnotationKindID { get }
    /// False for a kind that `AnnotationStage` leaves alone because another stage draws it
    /// (Redaction pixelates in the engine, before the Annotations).
    var drawnByAnnotationStage: Bool { get }
    /// True when the kind comes as an outline or a solid fill (Rectangle, Oval).
    var supportsFill: Bool { get }
    func paint(for annotation: Annotation) -> AnnotationPaint
    /// Whether a click at `point` (image points) is on the Annotation. Exact: the inside of a
    /// filled Annotation only, the stroke of an outline. `minimumWidth` makes a thin line
    /// grabbable (the stroke counts as at least that wide).
    func hit(_ annotation: Annotation, at point: CGPoint, minimumWidth: CGFloat) -> Bool
    /// The box the selection outline surrounds.
    func bounds(of annotation: Annotation) -> CGRect
    /// The points the selection shows handles at, which Select drags to resize.
    func handles(of annotation: Annotation) -> [CGPoint]
    /// The Annotation with its handle `index` dragged to `point`.
    func moveHandle(_ index: Int, to point: CGPoint, in annotation: Annotation) -> Annotation
    /// Draws the Annotation in the Export's context, which is already in image points (origin
    /// at the top left).
    func draw(_ annotation: Annotation, in context: CGContext)
    /// False when the Annotation is too small to see or to click (a drag that stopped where it
    /// started, a resize that collapsed it): the gesture that made it is thrown away.
    func isLargeEnough(_ annotation: Annotation) -> Bool
    /// The preview layer on the canvas; the canvas sets its frame. Runs once per Annotation.
    @MainActor func makeLayer(in context: AnnotationRenderContext) -> CALayer
    /// Brings the layer up to date with the Annotation: on every change to it, and for every
    /// Annotation when the zoom changes.
    @MainActor func update(_ layer: CALayer, for annotation: Annotation, in context: AnnotationRenderContext)
    /// An Annotation of this kind with every field set to something no default is, at `origin`
    /// (image points), `index` telling the samples of the registry's kinds apart. The Last Capture's
    /// round-trip stores and restores one of every kind and compares them field by field, so a field
    /// a kind adds is checked the day it exists: a kind with fields of its own (Text's string and
    /// size) overrides this and sets them to non-default values. A field missing from the `Codable`
    /// keys of `Annotation` or `AnnotationStyle` makes that comparison fail.
    func sampleAnnotation(id: Int, origin: CGPoint, index: Int) -> Annotation
}

nonisolated extension AnnotationKind {
    var drawnByAnnotationStage: Bool { true }
    var supportsFill: Bool { false }

    func sampleAnnotation(id: Int, origin: CGPoint, index: Int) -> Annotation {
        let style = AnnotationStyle(
            color: AnnotationColor(red: 0.1 + Double(index % 5) * 0.15, green: 0.6, blue: 0.3, alpha: 0.9),
            width: CGFloat(2 + index % 7), filled: index % 2 == 0)
        return Annotation(
            id: id, kind: self.id, start: origin, end: CGPoint(x: origin.x + 28, y: origin.y + 50), style: style)
    }

    /// A box at least `AnnotationLimits.smallestSize` points each way.
    func isLargeEnough(_ annotation: Annotation) -> Bool {
        let box = annotation.box
        return box.width >= AnnotationLimits.smallestSize && box.height >= AnnotationLimits.smallestSize
    }

    func hit(_ annotation: Annotation, at point: CGPoint, minimumWidth: CGFloat) -> Bool {
        let paint = paint(for: annotation)
        if paint.fill != nil, paint.path.contains(point) { return true }
        guard paint.stroke != nil else { return false }
        let ring = paint.path.copy(
            strokingWithWidth: max(paint.lineWidth, minimumWidth), lineCap: paint.lineCap,
            lineJoin: paint.lineJoin, miterLimit: 10)
        return ring.contains(point)
    }

    func bounds(of annotation: Annotation) -> CGRect {
        let paint = paint(for: annotation)
        let box = paint.path.boundingBoxOfPath
        guard paint.stroke != nil else { return box }
        return box.insetBy(dx: -paint.lineWidth / 2, dy: -paint.lineWidth / 2)
    }

    /// The four corners of the box, clockwise from the top left.
    func handles(of annotation: Annotation) -> [CGPoint] {
        let box = annotation.box
        return [
            CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
        ]
    }

    /// Dragging a corner keeps the opposite one where it is.
    func moveHandle(_ index: Int, to point: CGPoint, in annotation: Annotation) -> Annotation {
        let corners = handles(of: annotation)
        guard corners.indices.contains(index) else { return annotation }
        var copy = annotation
        copy.start = corners[(index + 2) % corners.count]
        copy.end = point
        return copy
    }

    func draw(_ annotation: Annotation, in context: CGContext) {
        let paint = paint(for: annotation)
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(paint.path)
        context.setLineWidth(paint.lineWidth)
        context.setLineCap(paint.lineCap)
        context.setLineJoin(paint.lineJoin)
        if let fill = paint.fill { context.setFillColor(fill) }
        if let stroke = paint.stroke { context.setStrokeColor(stroke) }
        switch (paint.fill != nil, paint.stroke != nil) {
        case (true, true): context.drawPath(using: .fillStroke)
        case (true, false): context.fillPath()
        case (false, true): context.strokePath()
        case (false, false): break
        }
    }

    @MainActor func makeLayer(in context: AnnotationRenderContext) -> CALayer { CAShapeLayer() }

    @MainActor func update(_ layer: CALayer, for annotation: Annotation, in context: AnnotationRenderContext) {
        guard let layer = layer as? CAShapeLayer else { return }
        let paint = paint(for: annotation)
        layer.path = paint.path
        layer.fillColor = paint.fill
        layer.strokeColor = paint.stroke
        layer.lineWidth = paint.lineWidth
        layer.lineCap = paint.lineCap.shapeLayerCap
        layer.lineJoin = paint.lineJoin.shapeLayerJoin
    }
}

nonisolated enum AnnotationLimits {
    /// The smallest an Annotation may be, in image points, each way (an Arrow: its length).
    static let smallestSize: CGFloat = 3
}

nonisolated extension CGLineCap {
    var shapeLayerCap: CAShapeLayerLineCap {
        switch self {
        case .round: .round
        case .square: .square
        default: .butt
        }
    }
}

nonisolated extension CGLineJoin {
    var shapeLayerJoin: CAShapeLayerLineJoin {
        switch self {
        case .round: .round
        case .bevel: .bevel
        default: .miter
        }
    }
}
